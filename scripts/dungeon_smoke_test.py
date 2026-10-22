#!/usr/bin/env python3
"""Actual dungeon collision, finite encounter, late join, the lobby map picker and map adoption over ENet."""
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
base = [sys.argv[1], "--headless", "--path", str(root)]
scene = "res://tests/dungeon_test.tscn"
map_scene = "res://tests/map_select_test.tscn"


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
    # The lobby picks the white room in the map test scene; a joiner started on the crypt takes it.
    pair_port = port()
    with log_path.open("w") as log:
        host = subprocess.Popen(base + [map_scene, "--", f"--port={pair_port}"], stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_for(log_path, "MAP_SELECT_HOST_READY:", host, timeout=60)
            client = subprocess.run(base + [map_scene, "--", "--dungeon", "--join=127.0.0.1", f"--port={pair_port}", "--expect-map=white_room"], capture_output=True, text=True, timeout=90)
            print(client.stdout + client.stderr)
            assert client.returncode == 0 and "MAP_ADOPTED: white_room" in client.stdout and "MAP_SELECT_CLIENT_OK:" in client.stdout
            host.wait(timeout=120)
            output = log_path.read_text()
            print(output)
            assert host.returncode == 0 and "MAP_SELECT_OK:" in output
            assert "ERROR" not in output + client.stdout + client.stderr
        finally:
            if host.poll() is None:
                host.terminate()
                host.wait(timeout=5)
    # The other way: the real game hosts the village; a real game started with --dungeon joins it.
    pair_port = port()
    client_log = pathlib.Path(directory) / "client.log"
    with log_path.open("w") as log, client_log.open("w") as joined:
        host = subprocess.Popen(base + ["--", "--host", f"--port={pair_port}"], stdout=log, stderr=subprocess.STDOUT)
        client = None
        try:
            wait_for(log_path, "Hosting on UDP", host, timeout=60)
            client = subprocess.Popen(base + ["--", "--dungeon", "--join=127.0.0.1", f"--port={pair_port}"], stdout=joined, stderr=subprocess.STDOUT)
            wait_for(client_log, "MAP_ADOPTED: village", client, timeout=30)
            wait_for(log_path, "SPAWNED ", host, timeout=60)
            time.sleep(2)
            output = client_log.read_text()
            print(output)
            assert "MAP: Village (village)" in output and "Host disconnected" not in output
            assert "ERROR" not in output + log_path.read_text()
        finally:
            for process in [client, host]:
                if process is not None and process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
print("PASS: dungeon geometry, gameplay, finite encounter, late join, lobby map picker and joiners adopting the host map")
