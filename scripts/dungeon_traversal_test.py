#!/usr/bin/env python3
"""Move the real player through every fixed dungeon route at 4x simulation speed."""
import pathlib
import socket
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
result = subprocess.run([sys.argv[1], "--headless", "--path", str(root),
    "res://tests/dungeon_traversal_test.tscn", "--", "--host", "--dungeon", f"--port={port}"],
    capture_output=True, text=True, timeout=240)
output = result.stdout + result.stderr
print(output)
assert result.returncode == 0 and "DUNGEON_TRAVERSAL_OK:" in output and "ERROR" not in output, "Traversal failed"
