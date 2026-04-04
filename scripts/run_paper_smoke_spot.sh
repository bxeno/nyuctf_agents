#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYS_FILE="${KEYS_FILE:-/opt/runner/keys.cfg}"

load_keys() {
  [[ -f "$KEYS_FILE" ]] || { echo "missing keys file: $KEYS_FILE"; exit 2; }
  while IFS= read -r raw; do
    line="${raw%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    [[ "$line" == *=* ]] || continue

    key="${line%%=*}"
    val="${line#*=}"
    key="$(echo "$key" | xargs)"
    val="$(echo "$val" | xargs)"
    [[ -z "$key" || -z "$val" ]] && continue

    case "$key" in
      OPENAI) export OPENAI_API_KEY="$val" ;;
      ANTHROPIC) export ANTHROPIC_API_KEY="$val" ;;
      OPENAI_API_KEY|ANTHROPIC_API_KEY) export "$key=$val" ;;
      *) ;;
    esac
  done < "$KEYS_FILE"
}

preflight_dataset() {
  local parent p1 p2
  parent="$(dirname "$ROOT_DIR")"
  p1="$parent/LLM_CTF_Database"
  p2="$parent/NYU_CTF_Bench"
  if [[ ! -d "$p1" && ! -d "$p2" ]]; then
    echo "paper_smoke preflight failed: expected dataset repo at $p1 or $p2"
    exit 2
  fi
}

main() {
  cd "$ROOT_DIR"
  load_keys
  preflight_dataset
  python3 scripts/run_paper_eval.py --limit 1 --repeats 1 --debug
}

main "$@"
