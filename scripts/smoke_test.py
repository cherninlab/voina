#!/usr/bin/env python3
"""Headless ENet integration check. Usage: python3 scripts/smoke_test.py GODOT"""
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
godot = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('GODOT', 'godot')
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
    probe.bind(('127.0.0.1', 0))
    port = probe.getsockname()[1]
base = [godot, '--headless', '--path', str(root)]
combat = subprocess.run(base + ['--script', 'tests/combat_test.gd'], capture_output=True, text=True, timeout=15)
print(combat.stdout, end='')
print(combat.stderr, end='')
assert combat.returncode == 0 and 'COMBAT_OK:' in combat.stdout
assert 'ERROR' not in combat.stdout + combat.stderr
stagger = subprocess.run(base + ['res://tests/stagger_test.tscn'], capture_output=True, text=True, timeout=15)
print(stagger.stdout, end='')
print(stagger.stderr, end='')
assert stagger.returncode == 0 and 'STAGGER_OK:' in stagger.stdout
assert 'ERROR' not in stagger.stdout + stagger.stderr
with tempfile.TemporaryDirectory() as directory:
    log_path = pathlib.Path(directory) / 'host.log'
    with log_path.open('w') as log:
        host = subprocess.Popen(base + ['--', '--host', f'--port={port}'], stdout=log, stderr=subprocess.STDOUT)
        try:
            time.sleep(1)
            result = subprocess.run(base + ['--', '--join=127.0.0.1', f'--port={port}', '--smoke-client'], capture_output=True, text=True, timeout=25)
            time.sleep(0.5)
            host_log = log_path.read_text()
            print(result.stdout, end='')
            print(result.stderr, end='')
            print(host_log, end='')
            assert result.returncode == 0 and 'SMOKE_OK:' in result.stdout
            assert 'DESPAWNED' in host_log
            assert 'SCRIPT ERROR' not in result.stdout + result.stderr + host_log
            assert 'ERROR:' not in result.stdout + result.stderr + host_log
        except subprocess.TimeoutExpired as error:
            print((error.stdout or b'').decode(errors='replace'))
            print((error.stderr or b'').decode(errors='replace'))
            print(log_path.read_text())
            raise
        finally:
            host.terminate()
            host.wait(timeout=5)
print('PASS: local two-process ENet integration and disconnect cleanup')
