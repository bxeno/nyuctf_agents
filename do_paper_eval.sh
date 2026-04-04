#!/usr/bin/env bash
set -euo pipefail

exec python3 scripts/run_paper_eval.py "$@"
