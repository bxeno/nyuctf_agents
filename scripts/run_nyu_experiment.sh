#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PATH="${VENV_PATH:-/opt/runner/.venv}"
OUT_DIR="${OUT_DIR:-/opt/runner/out}"

RUNNER="${RUNNER:-dcipher}"              # baseline|dcipher|single_executor
SPLIT="${SPLIT:-test}"                    # development|test
TRIALS="${TRIALS:-1}"
CHALLENGE="${CHALLENGE:-}"                # optional single challenge
MAX_CHALLENGES="${MAX_CHALLENGES:-0}"     # 0 = no cap
EXPERIMENT_NAME="${EXPERIMENT_NAME:-iter_eval}"
KEYS_FILE="${KEYS_FILE:-/opt/runner/keys.cfg}"
NYUCTF_AGENTS_REF="${NYUCTF_AGENTS_REF:-unknown}"
NYU_CTF_BENCH_REF="${NYU_CTF_BENCH_REF:-unknown}"

mkdir -p "$OUT_DIR"
cd "$ROOT_DIR"
source "$VENV_PATH/bin/activate"

TMP_CHALLENGE_LIST="$(mktemp)"
trap 'rm -f "$TMP_CHALLENGE_LIST"' EXIT

if [[ -n "$CHALLENGE" ]]; then
  printf '%s\n' "$CHALLENGE" > "$TMP_CHALLENGE_LIST"
else
  python3 - <<'PY' > "$TMP_CHALLENGE_LIST"
from nyuctf.dataset import CTFDataset
import os
split = os.environ.get("SPLIT", "test")
d = CTFDataset(split=split)
for k in sorted(d.keys()):
    print(k)
PY
fi

if [[ "$MAX_CHALLENGES" =~ ^[0-9]+$ ]] && [[ "$MAX_CHALLENGES" -gt 0 ]]; then
  head -n "$MAX_CHALLENGES" "$TMP_CHALLENGE_LIST" > "${TMP_CHALLENGE_LIST}.limited"
  mv "${TMP_CHALLENGE_LIST}.limited" "$TMP_CHALLENGE_LIST"
fi

if [[ "$RUNNER" == "dcipher" || "$RUNNER" == "single_executor" ]]; then
  [[ -f "$KEYS_FILE" ]] || { echo "missing keys file: $KEYS_FILE"; exit 2; }
fi

{
  echo "runner=$RUNNER"
  echo "split=$SPLIT"
  echo "trials=$TRIALS"
  echo "experiment_name=$EXPERIMENT_NAME"
  echo "nyuctf_agents_ref=$NYUCTF_AGENTS_REF"
  echo "nyu_ctf_bench_ref=$NYU_CTF_BENCH_REF"
  echo "max_challenges=$MAX_CHALLENGES"
  echo "challenge_override=${CHALLENGE:-<none>}"
  echo ""
  echo "challenges:"
  sed 's/^/- /' "$TMP_CHALLENGE_LIST"
} > "$OUT_DIR/experiment_plan.txt"

run_one() {
  local chal="$1"
  local trial="$2"
  case "$RUNNER" in
    baseline)
      python3 run_baseline.py \
        --split "$SPLIT" \
        --challenge "$chal" \
        --name "$EXPERIMENT_NAME" \
        --index "$trial" \
        --container-image ctfenv \
        --network ctfnet
      ;;
    dcipher)
      python3 run_dcipher.py \
        --split "$SPLIT" \
        --challenge "$chal" \
        --keys "$KEYS_FILE" \
        --experiment-name "$EXPERIMENT_NAME-t${trial}" \
        --container-image ctfenv:multiagent \
        --container-network ctfnet
      ;;
    single_executor)
      python3 run_single_executor.py \
        --split "$SPLIT" \
        --challenge "$chal" \
        --keys "$KEYS_FILE" \
        --experiment-name "$EXPERIMENT_NAME-t${trial}" \
        --container-image ctfenv:multiagent \
        --container-network ctfnet
      ;;
    *)
      echo "unsupported RUNNER=$RUNNER"
      exit 2
      ;;
  esac
}

TOTAL=$(wc -l < "$TMP_CHALLENGE_LIST" | xargs)
i=0
while IFS= read -r chal; do
  [[ -z "$chal" ]] && continue
  i=$((i+1))
  for trial in $(seq 1 "$TRIALS"); do
    echo "[challenge $i/$TOTAL][trial $trial/$TRIALS] $chal"
    run_one "$chal" "$trial"
  done
done < "$TMP_CHALLENGE_LIST"
