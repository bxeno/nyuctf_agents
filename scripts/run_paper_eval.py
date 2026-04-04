#!/usr/bin/env python3

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATASET_ROOTS = (
    REPO_ROOT.parent / "LLM_CTF_Database",
    REPO_ROOT.parent / "NYU_CTF_Bench",
)
EVENT_MAP = {
    "Finals": "CSAW-Finals",
    "Quals": "CSAW-Quals",
}
CATEGORY_MAP = {
    "Crypto": "crypto",
    "Forensics": "forensics",
    "Misc": "misc",
    "Pwn": "pwn",
    "Reversing": "rev",
    "Web": "web",
}


def resolve_dataset_root(explicit_root: str | None) -> Path:
    candidates = [Path(explicit_root).expanduser()] if explicit_root else []
    candidates.extend(DEFAULT_DATASET_ROOTS)
    for candidate in candidates:
        if candidate.is_dir():
            return candidate.resolve()
    candidate_list = ", ".join(str(path) for path in candidates)
    raise FileNotFoundError(
        f"Could not find dataset root. Checked: {candidate_list}. "
        "Use --dataset-root or create a sibling checkout named LLM_CTF_Database."
    )


def iter_tsv_challenges(challenge_list: Path):
    with challenge_list.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            yield row


def tsv_challenge_path(dataset_root: Path, row: dict[str, str]) -> Path:
    event = EVENT_MAP.get(row["Event"], row["Event"])
    category = CATEGORY_MAP.get(row["Category"], row["Category"].lower())
    return dataset_root / row["Year"] / event / category / row["Challenge"] / "challenge.json"


def load_json_challenges(dataset_json: Path):
    manifest = json.loads(dataset_json.read_text())
    for chal_id, metadata in manifest.items():
        yield {
            "id": chal_id,
            "category": metadata["category"],
            "challenge": metadata["challenge"],
            "path": metadata["path"],
        }


def cleanup_container(container_name: str):
    subprocess.run(["docker", "stop", container_name], check=False, capture_output=True)
    subprocess.run(["docker", "wait", container_name], check=False, capture_output=True)
    subprocess.run(["docker", "rm", container_name], check=False, capture_output=True)


def build_parser():
    parser = argparse.ArgumentParser(
        description="Run the paper-era NYU CTF benchmark against either the original or packaged dataset layout."
    )
    parser.add_argument("--dataset-root", default=None, help="path to the paper-era dataset checkout")
    parser.add_argument(
        "--challenge-list",
        default=None,
        help="path to challenge_list.tsv or test_dataset.json (defaults to auto-detect under <dataset-root>)",
    )
    parser.add_argument("-M", "--model", default="gpt-3.5-turbo-1106", help="model to evaluate")
    parser.add_argument("--backend", default=None, help="backend to pass through to llm_ctf_solve.py")
    parser.add_argument("-m", "--max-rounds", type=int, default=30, help="maximum rounds per attempt")
    parser.add_argument("-r", "--repeats", type=int, default=5, help="attempts per challenge")
    parser.add_argument("-L", "--logs-root", default="logs", help="directory for conversation logs")
    parser.add_argument("-n", "--container-name", default="ctfenv", help="client container name")
    parser.add_argument("-N", "--network", default="ctfnet", help="docker network for challenge and client")
    parser.add_argument("--limit", type=int, default=None, help="only run the first N challenges")
    parser.add_argument(
        "--category",
        action="append",
        default=[],
        help="paper category name filter; may be specified multiple times",
    )
    parser.add_argument(
        "--challenge",
        action="append",
        default=[],
        help="challenge name or dataset id filter; may be specified multiple times",
    )
    parser.add_argument("--dry-run", action="store_true", help="print commands without executing them")
    parser.add_argument("--debug", action="store_true", help="enable llm_ctf_solve.py debug logging")
    return parser


def resolve_manifest(dataset_root: Path, explicit_manifest: str | None):
    if explicit_manifest:
        manifest = Path(explicit_manifest).expanduser()
        if not manifest.is_file():
            raise FileNotFoundError(f"Manifest not found: {manifest}")
        return manifest.resolve()

    candidates = (
        dataset_root / "test_dataset.json",
        dataset_root / "challenge_list.tsv",
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(
        f"Could not find test_dataset.json or challenge_list.tsv under {dataset_root}"
    )


def main():
    args = build_parser().parse_args()
    dataset_root = resolve_dataset_root(args.dataset_root)
    manifest = resolve_manifest(dataset_root, args.challenge_list)

    categories = set(args.category)
    challenges = set(args.challenge)
    selected = []

    if manifest.name.endswith(".json"):
        for row in load_json_challenges(manifest):
            category = row["category"]
            challenge_name = row["challenge"]
            chal_id = row["id"]
            if categories and category not in categories:
                continue
            if challenges and challenge_name not in challenges and chal_id not in challenges:
                continue
            selected.append(row)
            if args.limit is not None and len(selected) >= args.limit:
                break
    else:
        for row in iter_tsv_challenges(manifest):
            category = CATEGORY_MAP.get(row["Category"], row["Category"].lower())
            challenge_name = row["Challenge"]
            if categories and row["Category"] not in categories and category not in categories:
                continue
            if challenges and challenge_name not in challenges:
                continue
            selected.append(row)
            if args.limit is not None and len(selected) >= args.limit:
                break

    if not selected:
        raise SystemExit("No challenges selected.")

    logs_root = Path(args.logs_root)
    solver = REPO_ROOT / "llm_ctf_solve.py"
    failures = []

    for row in selected:
        if manifest.name.endswith(".json"):
            challenge_json = dataset_root / row["path"] / "challenge.json"
            category = row["category"]
            challenge_name = row["challenge"]
        else:
            challenge_json = tsv_challenge_path(dataset_root, row)
            category = CATEGORY_MAP.get(row["Category"], row["Category"].lower())
            challenge_name = row["Challenge"]
        if not challenge_json.is_file():
            failures.append((challenge_name, f"missing challenge.json at {challenge_json}"))
            continue

        for attempt in range(1, args.repeats + 1):
            cleanup_container(args.container_name)
            log_path = logs_root / category / challenge_name / f"conversation.{args.model}.{attempt}.json"
            log_path.parent.mkdir(parents=True, exist_ok=True)

            cmd = [
                sys.executable,
                str(solver),
                "-n",
                args.container_name,
                "-N",
                args.network,
                "-M",
                args.model,
                "-m",
                str(args.max_rounds),
                "-L",
                str(log_path),
            ]
            if args.debug:
                cmd.append("-d")
            if args.backend:
                cmd.extend(["--backend", args.backend])
            cmd.append(str(challenge_json))

            print(f"[{attempt:02d}/{args.repeats:02d}] {category}/{challenge_name}")
            if args.dry_run:
                print(" ".join(cmd))
                continue

            completed = subprocess.run(cmd)
            if completed.returncode != 0:
                failures.append((challenge_name, f"attempt {attempt} exited with {completed.returncode}"))

    cleanup_container(args.container_name)

    if failures:
        print("\nFailures:")
        for name, reason in failures:
            print(f"- {name}: {reason}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
