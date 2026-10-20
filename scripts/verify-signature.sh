#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 1 || ! -d "$1/Contents" ]]; then
  echo 'Usage: bash scripts/verify-signature.sh /path/to/Automnt.app' >&2
  exit 2
fi
python3 "$TASK_ROOT/scripts/verify-signature.py" "$1"
