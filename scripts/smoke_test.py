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
assets = subprocess.run(base + ['--script', 'tests/asset_test.gd'], capture_output=True, text=True, timeout=15)
print(assets.stdout, end='')
print(assets.stderr, end='')
assert assets.returncode == 0 and 'ASSETS_OK:' in assets.stdout
assert 'ERROR' not in assets.stdout + assets.stderr
resolver = subprocess.run(base + ['--script', 'tests/hit_resolver_test.gd'], capture_output=True, text=True, timeout=15)
print(resolver.stdout, end='')
print(resolver.stderr, end='')
assert resolver.returncode == 0 and 'HIT_RESOLVER_OK:' in resolver.stdout
assert 'ERROR' not in resolver.stdout + resolver.stderr
cars = subprocess.run(base + ['--script', 'tests/car_test.gd'], capture_output=True, text=True, timeout=15)
print(cars.stdout, end='')
print(cars.stderr, end='')
assert cars.returncode == 0 and 'CAR_OK:' in cars.stdout
assert 'ERROR' not in cars.stdout + cars.stderr
# --fixed-fps steps physics at 1/60 s per frame without waiting for wall-clock time.
projectiles = subprocess.run(base + ['--fixed-fps', '60', 'res://tests/projectile_test.tscn'], capture_output=True, text=True, timeout=60)
print(projectiles.stdout, end='')
print(projectiles.stderr, end='')
assert projectiles.returncode == 0 and 'PROJECTILE_OK:' in projectiles.stdout
assert 'ERROR' not in projectiles.stdout + projectiles.stderr
for test, marker in ((['--script', 'tests/remote_motion_test.gd'], 'REMOTE_MOTION_OK:'), (['--fixed-fps', '60', 'res://tests/net_test.tscn'], 'NET_OK:')):
    run = subprocess.run(base + test, capture_output=True, text=True, timeout=60)
    print(run.stdout, end='')
    print(run.stderr, end='')
    assert run.returncode == 0 and marker in run.stdout
    assert 'ERROR' not in run.stdout + run.stderr
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

def run_pair(client_flags: list, marker: str, spawns: bool = True) -> str:
    """Start a host and one scripted client on a fresh port; return the host log."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(('127.0.0.1', 0))
        pair_port = probe.getsockname()[1]
    with tempfile.TemporaryDirectory() as directory:
        log_path = pathlib.Path(directory) / 'host.log'
        with log_path.open('w') as log:
            host = subprocess.Popen(base + ['--', '--host', f'--port={pair_port}'], stdout=log, stderr=subprocess.STDOUT)
            try:
                time.sleep(1)
                result = subprocess.run(base + ['--', '--join=127.0.0.1', f'--port={pair_port}'] + client_flags, capture_output=True, text=True, timeout=25)
                time.sleep(0.5)
                host_log = log_path.read_text()
                output = result.stdout + result.stderr + host_log
                print(output, end='')
                assert result.returncode == 0 and marker in result.stdout
                assert 'SCRIPT ERROR' not in output and 'ERROR:' not in output
                assert ('SPAWNED' in host_log) == spawns
                return host_log
            finally:
                host.terminate()
                host.wait(timeout=5)


# A client fires bolts at the host player over real ENet.
run_pair(['--projectile-smoke'], 'PROJECTILE_SMOKE_OK:')
# The client's net monitor sees the host's 60 Hz movement snapshots over a live ENet link.
run_pair(['--net-smoke'], 'NET_SMOKE_OK:')
# A different build is refused during authentication, before anything spawns.
assert 'BUILD_REFUSED' in run_pair(['--fake-build=0123456789ab', '--expect-version-mismatch'], 'VERSION_MISMATCH_OK:', spawns=False)
print('PASS: local two-process ENet integration and disconnect cleanup')
