#!/usr/bin/env python3
"""Two real ENet peers; delayed acknowledgements must not replay predicted actions."""
import heapq
import pathlib
import selectors
import socket
import subprocess
import sys
import tempfile
import threading
import time

root = pathlib.Path(__file__).resolve().parents[1]
godot = sys.argv[1]


def run_pair(delay):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reserve:
        reserve.bind(('127.0.0.1', 0))
        host_port = reserve.getsockname()[1]
    front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    front.bind(('127.0.0.1', 0))
    back.bind(('127.0.0.1', 0))
    front.setblocking(False)
    back.setblocking(False)
    selector = selectors.DefaultSelector()
    selector.register(front, selectors.EVENT_READ)
    selector.register(back, selectors.EVENT_READ)
    stop = threading.Event()

    def relay():
        client = None
        queue = []
        serial = 0
        while not stop.is_set():
            for key, _ in selector.select(0.005):
                try:
                    data, address = key.fileobj.recvfrom(65535)
                except BlockingIOError:
                    continue
                if key.fileobj is front:
                    client = address
                    target, outgoing = ('127.0.0.1', host_port), back
                elif client:
                    target, outgoing = client, front
                else:
                    continue
                serial += 1
                heapq.heappush(queue, (time.monotonic() + delay, serial, outgoing, data, target))
            while queue and queue[0][0] <= time.monotonic():
                _, _, outgoing, data, target = heapq.heappop(queue)
                outgoing.sendto(data, target)

    thread = threading.Thread(target=relay)
    thread.start()
    base = [godot, '--headless', '--path', str(root), '--script',
            'res://tests/prediction_latency_test.gd', '--', '--map=white_room',
            '--no-pve', '--no-forest-raiders']
    host = None
    try:
        with tempfile.TemporaryDirectory() as directory:
            log_path = pathlib.Path(directory) / 'host.log'
            with log_path.open('w') as log:
                host = subprocess.Popen(base + ['--host', f'--port={host_port}'], stdout=log, stderr=subprocess.STDOUT)
                time.sleep(0.8)
                flags = ['--delayed-approvals'] if delay else []
                client = subprocess.run(base + ['--join=127.0.0.1', f'--port={front.getsockname()[1]}'] + flags, capture_output=True, text=True, timeout=40)
                output = client.stdout + client.stderr + log_path.read_text()
                print(f'Added one-way delay: {delay:.3f} s\n{output}', flush=True)
                assert client.returncode == 0 and 'PREDICTION_LATENCY_OK:' in client.stdout
                assert 'ERROR:' not in output and 'SCRIPT ERROR' not in output
    finally:
        if host:
            host.terminate()
            try:
                host.wait(timeout=5)
            except subprocess.TimeoutExpired:
                host.kill()
                host.wait()
        stop.set()
        thread.join()
        selector.close()
        front.close()
        back.close()


run_pair(0.0)
run_pair(0.3)
print('PASS: normal and delayed ENet action approvals')
