#!/bin/sh
# Launch two visible clients from separate processes, sharing only read-only project sources.
set -eu
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT_BIN" --path . --position 0,80 -- --host &
HOST_PID=$!
trap 'kill "$HOST_PID" 2>/dev/null || true' EXIT INT TERM
sleep 1
"$GODOT_BIN" --path . --position 600,80 -- --join=127.0.0.1
