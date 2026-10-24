"""Runs the bridge generator's ageing attempts in parallel Blender processes,
then assembles the chosen attempt per route (plain Python 3, not Blender).

python3 scripts/art/bake_bridges.py content/environments/procedural_bridge_v1/layout.json \\
    content/environments/procedural_bridge_v1 [--review DIR] [--jobs 8] [--samples 32] [-- extra generator args]

Bullet runs on one core, and attempts are independent, so a series of eight
precise attempts takes about as long as the slowest one.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

GENERATOR = Path(__file__).resolve().parent / 'build_procedural_bridge.py'


def blender(arguments: list, log: Path) -> int:
    command = [shutil.which('blender') or 'blender', '--factory-startup', '-b', '--python-exit-code', '1',
               '--python', str(GENERATOR), '--'] + arguments
    with log.open('w') as handle:
        return subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT).returncode


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('layout')
    parser.add_argument('out')
    parser.add_argument('--review')
    parser.add_argument('--jobs', type=int, default=max(1, (os.cpu_count() or 4) - 2))
    parser.add_argument('--samples', default='32')
    parser.add_argument('--attempts', type=int, default=8)
    parser.add_argument('--routes', default='high_span,low_span')
    parser.add_argument('extra', nargs='*')
    options = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix='bridge-attempts-'))
    shared = [options.layout, options.out, '--samples', options.samples, '--work', str(work), '--attempts', str(options.attempts)]
    if options.review:
        shared += ['--review', options.review]
    started = time.time()
    jobs = [(route, n) for route in options.routes.split(',') for n in range(options.attempts)]

    def run(job):
        route, n = job
        code = blender(shared + ['--routes', route, '--only', str(n)] + options.extra, work / f'{route}_{n}.log')
        print(f'attempt {route} {n}: exit {code} after {time.time() - started:.0f}s', flush=True)
        return code

    with ThreadPoolExecutor(options.jobs) as pool:
        codes = list(pool.map(run, jobs))
    if any(codes):
        sys.exit(f'attempts failed; logs in {work}')
    for route in options.routes.split(','):
        log = work / f'{route}_assemble.log'
        if blender(shared + ['--routes', route, '--assemble'] + options.extra, log):
            sys.exit(f'assemble failed: {log}')
        print(next(line for line in log.read_text().splitlines() if line.startswith('BRIDGE_BAKE_OK')), flush=True)
    print(f'BRIDGES_DONE in {time.time() - started:.0f}s; attempt logs in {work}', flush=True)


main()
