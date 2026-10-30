#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
PYTHON_BIN="/Library/Developer/CommandLineTools/usr/bin/python3"
if [ ! -x "$PYTHON_BIN" ]; then
  PYTHON_BIN="python3"
fi
"$PYTHON_BIN" ipad/ipad_server.py --host 0.0.0.0 --port 9121
