#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PATH="${VENV_PATH:-/opt/runner/.venv}"
OUT_DIR="${OUT_DIR:-/opt/runner/out}"

RUNNER="${RUNNER:-dcipher}"              # baseline|dcipher|single_executor
SPLIT="${SPLIT:-test}"                    # development|test
TRIALS="${TRIALS:-1}"                     # default intentionally 1 for research iteration
CHALLENGE="${CHALLENGE:-}"                # optional single challenge
MAX_CHALLENGES="${MAX_CHALLENGES:-0}"     # 0 = no cap
EXPERIMENT_NAME="${EXPERIMENT_NAME:-iter_eval}"
KEYS_FILE="${KEYS_FILE:-/opt/runner/keys.cfg}"

mkdir -p "$OUT_DIR"
cd "$ROOT_DIR"
source "$VENV_PATH/bin/activate"

if [[ -n "$CHALLENGE" ]]; then
  printf '%s\n' "$CHALLENGE" > "$OUT_DIR/challenge_list.txt"
else
  python3 - <<'PY' > "$OUT_DIR/challenge_list.txt"
from nyuctf.dataset import CTFDataset
import os
split = os.environ.get("SPLIT", "test")
d = CTFDataset(split=split)
for k in sorted(d.keys()):
    print(k)
PY
fi

if [[ "$MAX_CHALLENGES" =~ ^[0-9]+$ ]] && [[ "$MAX_CHALLENGES" -gt 0 ]]; then
  head -n "$MAX_CHALLENGES" "$OUT_DIR/challenge_list.txt" > "$OUT_DIR/challenge_list.limited.txt"
  mv "$OUT_DIR/challenge_list.limited.txt" "$OUT_DIR/challenge_list.txt"
fi

if [[ "$RUNNER" == "dcipher" || "$RUNNER" == "single_executor" ]]; then
  [[ -f "$KEYS_FILE" ]] || { echo "missing keys file: $KEYS_FILE"; exit 2; }
fi

echo "runner=$RUNNER split=$SPLIT trials=$TRIALS" > "$OUT_DIR/experiment_plan.txt"

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

TOTAL=$(wc -l < "$OUT_DIR/challenge_list.txt" | xargs)
i=0
while IFS= read -r chal; do
  [[ -z "$chal" ]] && continue
  i=$((i+1))
  for trial in $(seq 1 "$TRIALS"); do
    echo "[challenge $i/$TOTAL][trial $trial/$TRIALS] $chal"
    if run_one "$chal" "$trial"; then
      echo "$chal,trial=$trial,status=ok" >> "$OUT_DIR/experiment_runs.csv"
    else
      echo "$chal,trial=$trial,status=fail" >> "$OUT_DIR/experiment_runs.csv"
    fi
  done
done < "$OUT_DIR/challenge_list.txt"
