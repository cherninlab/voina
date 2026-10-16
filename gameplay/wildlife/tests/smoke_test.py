#!/usr/bin/env python3
"""Wildlife behavior and actual ENet late-join checks. Usage: smoke_test.py GODOT"""
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[3]
godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
base = [godot, "--headless", "--path", str(root)]
local = subprocess.run(base + ["--script", "res://gameplay/wildlife/tests/flock_test.gd"], capture_output=True, text=True, timeout=15)
output = local.stdout + local.stderr
print(output, end="")
assert local.returncode == 0 and "WILDLIFE_OK:" in output and "ERROR" not in output

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
scene = "res://gameplay/wildlife/tests/network_test.tscn"
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "host.log"
    with path.open("w") as log:
        host = subprocess.Popen(base + [scene, "--", "--host", f"--port={port}"], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while "WILDLIFE_NETWORK_READY" not in path.read_text():
                assert host.poll() is None and time.monotonic() < deadline, path.read_text()
                time.sleep(0.1)
            client = subprocess.run(base + [scene, "--", "--join=127.0.0.1", f"--port={port}"], capture_output=True, text=True, timeout=15)
            host.wait(timeout=5)
            output = client.stdout + client.stderr + path.read_text()
            print(output, end="")
            assert client.returncode == 0 and host.returncode == 0
            assert "WILDLIFE_NETWORK_OK:" in output and "WILDLIFE_NETWORK_HOST_OK" in output
            assert "ERROR" not in output and "_FAIL" not in output
        finally:
            if host.poll() is None:
                host.terminate()
                host.wait(timeout=5)
print("PASS: wildlife behavior and two-process late join")
