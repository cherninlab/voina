#!/usr/bin/env python3
"""Lobby lifecycle and real ENet reconnect checks. Usage: session_smoke_test.py GODOT"""
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
base = [godot, "--headless", "--path", str(root), "res://tests/session_test.tscn"]

def port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]

local = subprocess.run(base + ["--fixed-fps", "60", "--", f"--port={port()}"], capture_output=True, text=True, timeout=20)
output = local.stdout + local.stderr
print(output, end="")
assert local.returncode == 0 and "SESSION_OK:" in output and "ERROR" not in output

listen = port()
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "host.log"
    with path.open("w") as log:
        host = subprocess.Popen(base + ["--", "--session-host", f"--port={listen}"], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while "SESSION_HOST_READY" not in path.read_text():
                assert host.poll() is None and time.monotonic() < deadline, path.read_text()
                time.sleep(0.1)
            client = subprocess.run(base + ["--", "--session-client", f"--port={listen}"], capture_output=True, text=True, timeout=35)
            host.wait(timeout=5)
            output = client.stdout + client.stderr + path.read_text()
            print(output, end="")
            assert client.returncode == 0 and host.returncode == 0
            assert "SESSION_CLIENT_OK:" in output and "SESSION_HOST_OK:" in output
            assert "ERROR" not in output and "SESSION_FAIL" not in output
        finally:
            if host.poll() is None:
                host.terminate()
                host.wait(timeout=5)
print("PASS: leave, host loss, clean rehost and authenticated reconnect")
