#!/usr/bin/env python3
"""Possessed villager (church yard) and raider (village, forest) checks, including real ENet late joining. Usage: mob_smoke_test.py GODOT"""
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GODOT", "godot")
base = [godot, "--headless", "--path", str(root)]
scene = "res://tests/mob_test.tscn"
local = subprocess.run(base + ["--fixed-fps", "60", scene], capture_output=True, text=True, timeout=60)
output = local.stdout + local.stderr
print(output, end="")
assert local.returncode == 0 and "MOB_OK:" in output and "ERROR" not in output
bodies = subprocess.run(base + ["--fixed-fps", "60", "res://tests/mob_body_test.tscn"], capture_output=True, text=True, timeout=60)
output = bodies.stdout + bodies.stderr
print(output, end="")
assert bodies.returncode == 0 and "MOB_BODY_OK:" in output and "ERROR" not in output
raiders = subprocess.run(base + ["--fixed-fps", "60", "res://tests/raider_test.tscn"], capture_output=True, text=True, timeout=90)
output = raiders.stdout + raiders.stderr
print(output, end="")
assert raiders.returncode == 0 and "RAIDER_OK:" in output and "ERROR" not in output
stains = subprocess.run(base + ["--script", "tests/stain_test.gd"], capture_output=True, text=True, timeout=60)
output = stains.stdout + stains.stderr
print(output, end="")
assert stains.returncode == 0 and "STAIN_OK:" in output and "ERROR" not in output

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
with tempfile.TemporaryDirectory() as directory:
    log_path = pathlib.Path(directory) / "host.log"
    with log_path.open("w") as log:
        host = subprocess.Popen(base + [scene, "--", "--host", "--mob-network", f"--port={port}"], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 20
            while "MOB_NETWORK_READY" not in log_path.read_text():
                assert host.poll() is None and time.monotonic() < deadline, log_path.read_text()
                time.sleep(0.1)
            # Join only after a villager pounced on the host player and lost health itself.
            client = subprocess.run(base + [scene, "--", "--join=127.0.0.1", "--mob-network", f"--port={port}"], capture_output=True, text=True, timeout=20)
            host.wait(timeout=5)
            output = client.stdout + client.stderr + log_path.read_text()
            print(output, end="")
            assert client.returncode == 0 and host.returncode == 0
            assert "MOB_NETWORK_OK:" in output and "MOB_NETWORK_HOST_OK:" in output
            assert "ERROR" not in output and "MOB_FAIL" not in output
        finally:
            if host.poll() is None:
                host.terminate()
                host.wait(timeout=5)
print("PASS: villager behaviour, yard navigation, raiders, bodies, stains and two-process late join")
