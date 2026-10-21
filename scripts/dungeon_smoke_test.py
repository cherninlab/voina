#!/usr/bin/env python3
"""Actual dungeon collision, finite encounter, late join and map agreement over ENet."""
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
base = [sys.argv[1], "--headless", "--path", str(root)]
scene = "res://tests/dungeon_test.tscn"


def port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def wait_for(log, marker, process, timeout=15):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        output = log.read_text()
        if marker in output:
            return
        assert process.poll() is None, output
        time.sleep(0.1)
    raise AssertionError(log.read_text())


with tempfile.TemporaryDirectory() as directory:
    log_path = pathlib.Path(directory) / "host.log"
    pair_port = port()
    with log_path.open("w") as log:
        host = subprocess.Popen(base + [scene, "--", "--host", "--dungeon", f"--port={pair_port}"], stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_for(log_path, "DUNGEON_HOST_READY:", host)
            client = subprocess.run(base + [scene, "--", "--dungeon", "--join=127.0.0.1", f"--port={pair_port}"], capture_output=True, text=True, timeout=20)
            print(client.stdout + client.stderr)
            assert client.returncode == 0 and "DUNGEON_CLIENT_OK:" in client.stdout
            host.wait(timeout=20)
            output = log_path.read_text()
            print(output)
            assert host.returncode == 0 and "DUNGEON_OK:" in output
            assert "ERROR" not in output + client.stdout + client.stderr
        finally:
            if host.poll() is None:
                host.terminate()
                host.wait(timeout=5)
    # Flag mismatch is refused in either direction, including with build bypass enabled.
    for host_map, client_map in [(["--dungeon"], []), ([], ["--dungeon"])]:
        pair_port = port()
        with log_path.open("w") as log:
            host = subprocess.Popen(base + ["--", "--host", "--allow-version-mismatch", f"--port={pair_port}", *host_map], stdout=log, stderr=subprocess.STDOUT)
            try:
                wait_for(log_path, "Hosting on UDP", host)
                client = subprocess.run(base + ["--", "--join=127.0.0.1", "--allow-version-mismatch", "--expect-version-mismatch", f"--port={pair_port}", *client_map], capture_output=True, text=True, timeout=15)
                print(client.stdout + client.stderr)
                assert client.returncode == 0 and "MAP_MISMATCH:" in client.stdout and "VERSION_MISMATCH_OK:" in client.stdout
                assert "SPAWNED" not in log_path.read_text()
                assert "ERROR" not in client.stdout + client.stderr + log_path.read_text()
            finally:
                host.terminate()
                host.wait(timeout=5)
print("PASS: dungeon geometry, gameplay, finite encounter, late join and bidirectional map authentication")
