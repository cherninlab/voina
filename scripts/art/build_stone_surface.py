"""Tileable procedural PBR maps for the faces of dressed dungeon wall stones (T-180).

blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_stone_surface.py -- \
    [outdir] [--seed 180] [--only limestone,sandstone,granite] [--size 2048] \
    [--no-maps] [--no-render] [--samples 128] [--strength 0.75] [--study limestone] [--preview DIR]

Every layer is synthesised in numpy on a periodic domain: FFT-filtered noise, Worley
cells on a wrapped grid, and pits and chips stamped modulo the tile. All derived maps
(normals, AO, cavity masks) use wrapped neighbours, so the tile repeats exactly.
One tile is 1.8 m of wall (dungeon_surface surface() density 0.555): 0.88 mm per pixel
at 2048 px. Writes <variant>/{albedo,normal_gl,roughness,height,ao}.png, review/ Cycles
renders plus a 3 x 3 tiling sheet, and stone_surface.json (seed, statistics, seam check,
file hashes). No external images, scans or node assets are read.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
import numpy as np
from mathutils import Vector, noise

from procgen import core

OUT = core.ROOT / 'content/environments/procedural_stone_surface_v1'
TILE_MM = 1800.0
DENSITY = 0.555
MAPS = ('albedo', 'normal_gl', 'roughness', 'height', 'ao')
STUDY = (0.5, 0.75, 1.0)

# Linear albedo, height layers in millimetres, densities per square metre.
VARIANTS = {
    # Grey-beige limestone: medium dressing scars, sharp chips, a few solution pockets.
    'limestone': dict(
        color=(0.255, 0.246, 0.222), grime=(0.40, 0.38, 0.34), fresh=(0.34, 0.33, 0.31),
        undulation=0.7, scars=((62.0, 3.6), (24.0, 1.3)), scar_round=0.12, scar_tone=0.05, medium=0.2,
        pockets=dict(per_m2=60, r=(4.0, 12.0), alpha=2.5, depth=(0.18, 0.32)), grit=0.09, grains=0.0, pores=0.02, laminae=0.0,
        pits=dict(per_m2=2600, r=(0.8, 7.5), alpha=2.9, depth=(0.5, 0.95)),
        chips=dict(per_m2=9, r=(5.0, 17.0), depth=(0.5, 1.4)),
        roughness=0.74, mottle=0.06, wear=0.3, grime_amount=0.8),
    # Warm grey-brown sandstone: softer eroded relief, sand grain, honeycomb pitting, faint bedding.
    'sandstone': dict(
        color=(0.245, 0.204, 0.166), grime=(0.42, 0.39, 0.35), fresh=(0.29, 0.25, 0.21),
        undulation=0.8, scars=((58.0, 2.8), (22.0, 0.8)), scar_round=0.3, scar_tone=0.05, medium=0.28,
        pockets=dict(per_m2=30, r=(4.0, 10.0), alpha=2.5, depth=(0.15, 0.28)), grit=0.12, grains=0.06, pores=0.015, laminae=0.18,
        pits=dict(per_m2=3200, r=(0.8, 6.0), alpha=2.8, depth=(0.5, 0.9), cluster=True),
        chips=dict(per_m2=5, r=(5.0, 15.0), depth=(0.4, 1.0)),
        roughness=0.84, mottle=0.05, wear=0.24, grime_amount=0.75),
    # Dark grey granite: crisp point-dressed facets and pocks, fine crystal speckle.
    'granite': dict(
        color=(0.125, 0.125, 0.122), grime=(0.5, 0.49, 0.47), fresh=(0.19, 0.19, 0.185),
        undulation=0.5, scars=((44.0, 2.8), (16.0, 1.2)), scar_round=0.06, scar_tone=0.04, medium=0.14,
        pockets=None, grit=0.07, grains=0.0, pores=0.012, laminae=0.0,
        pits=dict(per_m2=3400, r=(0.8, 4.5), alpha=2.6, depth=(0.5, 0.9)),
        chips=dict(per_m2=26, r=(4.0, 13.0), depth=(0.4, 1.2)),
        roughness=0.7, mottle=0.04, wear=0.22, grime_amount=0.65),
}


def parse() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog='build_stone_surface.py')
    parser.add_argument('outdir', nargs='?', default=str(OUT))
    parser.add_argument('--seed', type=int, default=180)
    parser.add_argument('--only', default='', help='comma-separated variants')
    parser.add_argument('--size', type=int, default=2048)
    parser.add_argument('--no-maps', action='store_true', help='render the maps already in outdir')
    parser.add_argument('--no-render', action='store_true')
    parser.add_argument('--samples', type=int, default=128)
    parser.add_argument('--strength', type=float, default=0.75, help='review normal_strength (surface() relief)')
    parser.add_argument('--study', default='', help='variant for the relief (normal strength) comparison render')
    parser.add_argument('--preview', default='', help='directory for quick numpy-lit previews')
    return parser.parse_args(core.args())


def smoothstep(e0: float, e1: float, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Torus:
    """Periodic field synthesis on an n x n tile spanning TILE_MM millimetres."""

    def __init__(self, n: int, seed: int, variant: str):
        self.n, self.seed, self.variant = n, seed, variant
        self.mm = TILE_MM / n
        fy = np.fft.fftfreq(n, 1.0 / n)[:, None]
        fx = np.fft.rfftfreq(n, 1.0 / n)[None, :]
        self.k = np.sqrt(fy * fy + fx * fx)  # cycles per tile
        grid = np.arange(n, dtype=np.float32)
        self.yy, self.xx = np.meshgrid(grid, grid, indexing='ij')

    def rng(self, *keys) -> np.random.Generator:
        digest = hashlib.sha256(json.dumps([self.seed, self.variant, *keys]).encode()).digest()
        return np.random.default_rng(int.from_bytes(digest[:8], 'little'))

    def spectral(self, white: np.ndarray, filt: np.ndarray) -> np.ndarray:
        return np.fft.irfft2(np.fft.rfft2(white) * filt, s=white.shape).astype(np.float32)

    def band(self, key: str, lo_mm: float, hi_mm: float, slope: float = 1.0) -> np.ndarray:
        """Gaussian noise with wavelengths lo_mm..hi_mm, amplitude ~ f^-slope, unit std."""
        k_lo, k_hi = TILE_MM / hi_mm, TILE_MM / lo_mm
        with np.errstate(all='ignore'):
            filt = k_lo ** slope / (1.0 + (k_lo / self.k) ** 4) / (1.0 + (self.k / k_hi) ** 4) * self.k ** -slope
        filt[0, 0] = 0.0
        out = self.spectral(self.rng('band', key).standard_normal((self.n, self.n)), filt)
        return out / out.std()

    def blur(self, field: np.ndarray, sigma_mm: float) -> np.ndarray:
        sigma = sigma_mm / self.mm
        return self.spectral(field, np.exp(-2.0 * math.pi ** 2 * sigma * sigma * (self.k / self.n) ** 2))

    def sample(self, field: np.ndarray, y: np.ndarray, x: np.ndarray) -> np.ndarray:
        """Bilinear lookup with wrap-around at fractional pixel positions."""
        n = self.n
        y0, x0 = np.floor(y), np.floor(x)
        ty, tx = (y - y0).astype(np.float32), (x - x0).astype(np.float32)
        y0, x0 = y0.astype(np.int64) % n, x0.astype(np.int64) % n
        y1, x1 = (y0 + 1) % n, (x0 + 1) % n
        top = field[y0, x0] * (1 - tx) + field[y0, x1] * tx
        bottom = field[y1, x0] * (1 - tx) + field[y1, x1] * tx
        return top * (1 - ty) + bottom * ty

    def warp(self, field: np.ndarray, key: str, size_mm: float, amount_mm: float) -> np.ndarray:
        a = amount_mm / self.mm
        dy = self.band(key + '/wy', size_mm * 0.5, size_mm * 2.0)
        dx = self.band(key + '/wx', size_mm * 0.5, size_mm * 2.0)
        return self.sample(field, self.yy + dy * a, self.xx + dx * a)

    def worley(self, key: str, size_mm: float, warp: float = 0.0):
        """F1, F2 (cell units) and a random id per cell of a jittered grid that wraps;
        `warp` (cell units) bends the cell walls into irregular grain outlines."""
        n = self.n
        cells = max(2, round(TILE_MM / size_mm))
        r = self.rng('worley', key)
        jitter = r.random((cells, cells, 2)).astype(np.float32)
        ident = r.random((cells, cells)).astype(np.float32)
        uy = (self.yy + 0.5) * (cells / n)
        ux = (self.xx + 0.5) * (cells / n)
        if warp:
            uy = uy + warp * self.band(key + '/wy', size_mm * 0.7, size_mm * 4.0)
            ux = ux + warp * self.band(key + '/wx', size_mm * 0.7, size_mm * 4.0)
        by, bx = np.floor(uy).astype(np.int64), np.floor(ux).astype(np.int64)
        f1 = np.full((n, n), 9.0, np.float32)
        f2 = np.full((n, n), 9.0, np.float32)
        cid = np.zeros((n, n), np.float32)
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                cy, cx = by + dj, bx + di
                wy, wx = cy % cells, cx % cells
                dy = uy - (cy + jitter[wy, wx, 0])
                dx = ux - (cx + jitter[wy, wx, 1])
                d = np.sqrt(dy * dy + dx * dx)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                cid = np.where(closer, ident[wy, wx], cid)
                f1 = np.where(closer, d, f1)
        return f1, f2, cid

    def scars(self, key: str, size_mm: float, depth_mm: float, round_off: float = 0.12):
        """Flake scars of hand dressing: shallow elongated dishes on a wrapped jittered grid,
        whose rounded lower envelope leaves soft ridges where neighbouring scars meet.
        Returns height in mm (0 at dish bottoms) and a per-scar tone in -1..1, blended softly."""
        n = self.n
        cells = max(2, round(TILE_MM / size_mm))
        r = self.rng('scars', key)
        jitter = r.random((cells, cells, 2)).astype(np.float32)
        offset = r.uniform(0.0, 0.45, (cells, cells)).astype(np.float32)
        curve = r.uniform(0.7, 1.35, (cells, cells)).astype(np.float32)
        angle = r.uniform(0.0, math.pi, (cells, cells)).astype(np.float32)
        aspect = r.uniform(1.0, 1.9, (cells, cells)).astype(np.float32)
        tone = r.uniform(-1.0, 1.0, (cells, cells)).astype(np.float32)
        scale = cells / n
        wy = self.band(key + '/wy', size_mm * 0.6, size_mm * 3.0) * 0.16
        wx = self.band(key + '/wx', size_mm * 0.6, size_mm * 3.0) * 0.16
        uy = (self.yy + 0.5) * scale + wy
        ux = (self.xx + 0.5) * scale + wx
        by, bx = np.floor(uy).astype(np.int64), np.floor(ux).astype(np.int64)
        bowls, tones = [], []
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                cy, cx = by + dj, bx + di
                iy, ix = cy % cells, cx % cells
                dy = uy - (cy + jitter[iy, ix, 0])
                dx = ux - (cx + jitter[iy, ix, 1])
                c, s = np.cos(angle[iy, ix]), np.sin(angle[iy, ix])
                a, b = dx * c + dy * s, -dx * s + dy * c
                asp = aspect[iy, ix]
                bowls.append(offset[iy, ix] + 4.0 * curve[iy, ix] * (a * a / asp + b * b * asp))
                tones.append(tone[iy, ix])
        bowls = np.stack(bowls)
        low = bowls.min(axis=0)
        weights = np.exp(-(bowls - low) / round_off)
        total = weights.sum(axis=0)
        envelope = low - round_off * np.log(total)
        tone_weights = np.exp(-(bowls - low) / 0.04)
        blended = (tone_weights * np.stack(tones)).sum(axis=0) / tone_weights.sum(axis=0)
        envelope = 1.4 * np.tanh(np.maximum(envelope, 0.0) / 1.4)
        return (depth_mm * envelope).astype(np.float32), blended.astype(np.float32)

    def stamp_window(self, cy: float, cx: float, reach: float):
        """Wrapped index window around a point and the float offsets of its pixels."""
        half = int(math.ceil(reach)) + 1
        oy = np.arange(-half, half + 1) + int(math.floor(cy))
        ox = np.arange(-half, half + 1) + int(math.floor(cx))
        window = np.ix_(oy % self.n, ox % self.n)
        return window, (oy + 0.5 - cy)[:, None], (ox + 0.5 - cx)[None, :]

    def pits(self, key: str, per_m2: float, r: tuple, alpha: float, depth: tuple, cluster: bool = False, density=None):
        """Weathering and tooling pits carved as irregular bowls; returns height in mm (<= 0)."""
        g = self.rng('pits', key)
        count = int(per_m2 * (TILE_MM / 1000.0) ** 2)
        a1 = 1.0 - alpha
        radii = (r[0] ** a1 + g.random(count) * (r[1] ** a1 - r[0] ** a1)) ** (1.0 / a1)
        cy, cx = g.random(count) * self.n, g.random(count) * self.n
        depths = radii * g.uniform(depth[0], depth[1], count)
        aspects = g.uniform(1.0, 1.5, count)
        angles = g.uniform(0.0, math.pi, count)
        accept = np.ones((self.n, self.n), np.float32) if density is None else density
        if cluster:
            # Alveolar weathering gathers small pits in loose honeycomb patches.
            accept = accept * (0.25 + 0.75 * smoothstep(-0.6, 1.0, self.band(key + '/cluster', 30.0, 140.0)))
        keep = g.random(count) < accept[cy.astype(int) % self.n, cx.astype(int) % self.n]
        lobes = g.normal(0.0, 1.0, (count, 3)) * np.array([0.08, 0.045, 0.025])
        phases = g.uniform(0.0, 2.0 * math.pi, (count, 3))
        layer = np.zeros((self.n, self.n), np.float32)
        for i in np.nonzero(keep)[0]:
            rad = radii[i] / self.mm
            window, dy, dx = self.stamp_window(cy[i], cx[i], rad * aspects[i] * 1.5)
            c, s = math.cos(angles[i]), math.sin(angles[i])
            a = (dx * c + dy * s) / (rad * aspects[i])
            b = (-dx * s + dy * c) / rad
            d = np.sqrt(a * a + b * b) * outline(np.arctan2(b, a), lobes[i], phases[i])
            bowl = -depths[i] * np.clip(1.0 - d * d, 0.0, None) ** 0.55
            layer[window] = np.minimum(layer[window], bowl)
        return layer, int(keep.sum())

    def chips(self, key: str, per_m2: float, r: tuple, depth: tuple):
        """Small spalls: shallow scoops feathered on one side with a sharp break on the other."""
        g = self.rng('chips', key)
        count = int(per_m2 * (TILE_MM / 1000.0) ** 2)
        radii = np.exp(g.uniform(math.log(r[0]), math.log(r[1]), count))
        cy, cx = g.random(count) * self.n, g.random(count) * self.n
        depths = g.uniform(depth[0], depth[1], count) * np.sqrt(radii / r[1])
        aspects = g.uniform(1.15, 1.9, count)
        angles = g.uniform(0.0, 2.0 * math.pi, count)
        breaks = angles + g.uniform(-0.6, 0.6, count)
        lobes = g.normal(0.0, 1.0, (count, 3)) * np.array([0.11, 0.06, 0.035])
        phases = g.uniform(0.0, 2.0 * math.pi, (count, 3))
        layer = np.zeros((self.n, self.n), np.float32)
        mask = np.zeros((self.n, self.n), np.float32)
        for i in range(count):
            rad = radii[i] / self.mm
            window, dy, dx = self.stamp_window(cy[i], cx[i], rad * aspects[i] * 1.6)
            c, s = math.cos(angles[i]), math.sin(angles[i])
            a = (dx * c + dy * s) / (rad * aspects[i])
            b = (-dx * s + dy * c) / rad
            d = np.sqrt(a * a + b * b) * outline(np.arctan2(b, a), lobes[i], phases[i])
            inside = np.clip((1.0 - d) / 0.1, 0.0, 1.0)
            along = (dx * math.cos(breaks[i]) + dy * math.sin(breaks[i])) / (rad * aspects[i])
            ramp = np.clip(0.5 + 0.6 * along, 0.0, 1.0)
            # Conchoidal floor: deepest under the break, rising towards the feathered side.
            floor = (0.35 + 0.65 * ramp) * (1.0 - 0.3 * np.clip(d, 0.0, 1.0) ** 2)
            scoop = -depths[i] * inside * floor
            layer[window] = np.minimum(layer[window], scoop)
            mask[window] = np.maximum(mask[window], inside)
        return layer, mask


def outline(theta: np.ndarray, lobes: np.ndarray, phases: np.ndarray) -> np.ndarray:
    """Irregular but whole outline: radial scale from 2nd-4th order lobes (no fragments)."""
    wave = sum(lobes[k] * np.cos((k + 2) * theta + phases[k]) for k in range(len(lobes)))
    return 1.0 + np.clip(wave, -0.3, 0.3)


def horizon_ao(t: Torus, h: np.ndarray, radius_mm: float = 24.0, directions: int = 16) -> np.ndarray:
    """Cosine-weighted ambient occlusion from the height field's horizon angles (wraps)."""
    steps = sorted({max(1, round(radius_mm / t.mm * (i / 10.0) ** 1.6)) for i in range(1, 11)})
    occlusion = np.zeros_like(h)
    for k in range(directions):
        angle = 2.0 * math.pi * (k + 0.5) / directions
        best = np.zeros_like(h)
        for s in steps:
            oy, ox = round(s * math.sin(angle)), round(s * math.cos(angle))
            if oy == 0 and ox == 0:
                continue
            dist = math.hypot(oy, ox) * t.mm
            fade = max(0.0, 1.0 - (dist / radius_mm) ** 2)
            rise = (np.roll(h, (-oy, -ox), (0, 1)) - h) / dist * fade
            np.maximum(best, rise, out=best)
        occlusion += best * best / (1.0 + best * best)  # sin^2 of the horizon elevation
    return 1.0 - occlusion / directions


def normals(t: Torus, h: np.ndarray) -> np.ndarray:
    """Unit normals, x right and y towards the top of the image (OpenGL)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2.0 * t.mm)
    dup = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) / (2.0 * t.mm)
    n = np.stack([-dx, -dup, np.ones_like(h)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def mineral_albedo(t: Torus, spec: dict, name: str):
    """Base stone colour before weathering: mineral variation, grains and speckle.
    Returns linear RGB and, for granite, the (mica, feldspar) masks used for relief."""
    n = t.n
    lum = (1.0 + spec['mottle'] * t.band('mottle-l', 18.0, 140.0, 0.6)
           + 0.6 * spec['mottle'] * t.warp(t.band('mottle-m', 3.0, 18.0, 0.5), 'mottle-w', 20.0, 3.0)
           + 0.035 * t.band('mottle-s', t.mm, 2.5, 0.0))
    base = np.array(spec['color'], np.float32)
    grey = np.full(3, base.mean(), np.float32)
    # Weathering shifts patches between greyer and warmer stone without changing much in value.
    saturation = np.clip(1.0 + 0.3 * t.warp(t.band('sat', 12.0, 110.0, 0.7), 'sat-w', 40.0, 6.0), 0.5, 1.5)
    color = (grey + (base - grey) * saturation[..., None]) * lum[..., None]
    minerals = None
    if name == 'limestone':
        # Sparse shell fragments and dark specks in a fine micritic ground.
        f1, _, cid = t.worley('flecks', 4.0)
        light = (cid > 0.965) * smoothstep(0.45, 0.2, f1)
        dark = (cid < 0.02) * smoothstep(0.3, 0.12, f1)
        color *= (1.0 + 0.16 * light - 0.28 * dark)[..., None]
    elif name == 'sandstone':
        # Sand grains, iron specks and faint bedding laminae (stone is laid on its bed).
        grain = t.rng('grain').standard_normal((n, n)).astype(np.float32)
        f1, _, cid = t.worley('iron', 1.8)
        iron = (cid < 0.03) * smoothstep(0.35, 0.15, f1)
        phase = (t.yy * t.mm / 9.0 + 1.6 * t.band('lam-w', 20.0, 160.0)) * 2.0 * math.pi
        lam = np.sin(phase) * smoothstep(-0.8, 1.0, t.band('lam-a', 40.0, 200.0))
        color *= (1.0 + 0.045 * grain - 0.3 * iron + 0.03 * lam)[..., None]
        color[..., 0] *= 1.0 + 0.015 * lam
        color[..., 2] *= 1.0 - 0.02 * lam
    elif name == 'granite':
        # Interlocking crystals: blocky pale feldspar, grey glassy quartz, clots of black mica.
        _, _, fid = t.worley('feldspar', 3.6, warp=0.22)
        _, _, qid = t.worley('quartz', 3.0, warp=0.3)
        m1, _, mid = t.worley('mica', 1.5, warp=0.3)
        clots = smoothstep(-0.2, 1.4, t.band('mica-clots', 4.0, 18.0))
        feldspar = t.blur((fid < 0.24).astype(np.float32), 0.35 * t.mm)
        mica = t.blur(((mid < 0.6 * clots) & (m1 < 0.5)).astype(np.float32), 0.35 * t.mm) * (1.0 - 0.8 * feldspar)
        quartz = 1.0 - feldspar - mica
        q_shade = 0.8 + 0.4 * qid
        f_shade = 0.85 + 0.3 * np.modf(fid * 37.0)[0]
        mineral = (base * q_shade[..., None] * quartz[..., None]
                   + np.array([0.27, 0.262, 0.25], np.float32) * (f_shade * feldspar)[..., None]
                   + np.array([0.03, 0.031, 0.032], np.float32) * mica[..., None])
        # Patina and grime soften the crystal contrast on an old wall.
        color = color / base * (0.6 * mineral + 0.4 * base)
        minerals = (mica, feldspar)
    return color.astype(np.float32), minerals


def synthesize(name: str, spec: dict, n: int, seed: int) -> dict:
    t = Torus(n, seed, name)
    # Zones of 10-30 cm where the face is more worn or more broken, so it is not uniform noise.
    zone = smoothstep(-0.9, 0.9, t.band('zone', 100.0, 320.0, 0.5))
    # Undulation 2-8 cm: the gently pillowed, hand-dressed face.
    und = t.band('und', 20.0, 90.0, 1.0) * spec['undulation']
    # Flake scars from dressing, a coarse and a fine generation.
    height = und
    scar_tone = np.zeros((n, n), np.float32)
    for i, (size, depth) in enumerate(spec['scars']):
        relief, tone = t.scars(f'scar{i}', size, depth, spec['scar_round'])
        height = height + relief * (1.0 if i == 0 else 0.5 + 0.8 * zone)
        scar_tone += tone * depth
    scar_tone /= sum(d for _, d in spec['scars'])
    # Broad-band roughness 2.5-40 mm with slightly flattened worn highs.
    med = t.band('med', 2.5, 40.0, 1.0)
    med = (0.7 * med - 0.3 * np.log1p(np.exp(-2.0 * med))) * spec['medium']
    height = height + med
    # Solution pockets: a sparse second population of wide, shallow, irregular hollows.
    if spec['pockets']:
        pockets, _ = t.pits('pockets', density=0.3 + 0.7 * zone, **spec['pockets'])
        height += t.blur(pockets, 0.6 * t.mm)
    pits, pit_count = t.pits('pits', density=0.3 + 0.7 * zone, **spec['pits'])
    chips, chip_mask = t.chips('chips', **spec['chips'])
    carved = t.blur(np.minimum(pits, chips), 0.45 * t.mm)
    height += carved
    # Grit: fine granular relief, stronger inside pits and pockets.
    cavity_fine = t.blur(height, 3.0) - height
    grit = t.band('grit', t.mm, 3.0, 0.0) * spec['grit'] * (0.7 + 0.6 * zone + 0.5 * smoothstep(0.05, 0.6, cavity_fine))
    if spec['grains'] > 0:
        grains = (t.rng('grains').random((n, n)) > 0.93).astype(np.float32)
        grit += t.blur(grains, 0.55 * t.mm) * spec['grains'] * 3.0
    if spec['laminae']:
        # Bedding: the stone is laid on its bed, so laminae run level and erode a little unevenly.
        phase = (t.yy * t.mm / 9.0 + 1.6 * t.band('lam-w', 20.0, 160.0)) * 2.0 * math.pi
        height += spec['laminae'] * np.sin(phase) * smoothstep(-0.8, 1.0, t.band('lam-a', 40.0, 200.0))
    # Pores: sub-millimetre holes that read as fine dark stipple.
    pores = t.blur((t.rng('pores').random((n, n)) > 1.0 - spec['pores']).astype(np.float32), 0.5 * t.mm)
    height += grit - 0.35 * pores
    albedo, minerals = mineral_albedo(t, spec, name)
    albedo *= (1.0 + spec['scar_tone'] * scar_tone)[..., None]
    if minerals:
        # Weathering leaves feldspar standing slightly proud and plucks out mica.
        mica, feldspar = minerals
        height += 0.06 * feldspar - 0.12 * mica
    # Masks from the final relief.
    ao = horizon_ao(t, height)
    cav_s = t.blur(height, 2.0) - height  # pits, chips, pockets
    cav_m = t.blur(height, 12.0) - height  # bottoms of the dressing scars
    breakup = t.band('grime-v', 3.0, 30.0, 0.5)
    dirt = smoothstep(0.2, 0.9, cav_s + 0.08 * breakup) * (1.0 - chip_mask)
    lows = smoothstep(0.4, 2.4, cav_m) * smoothstep(-1.0, 1.0, breakup)
    grime = np.clip(0.85 * dirt + 0.3 * lows + 0.3 * smoothstep(0.85, 0.45, ao), 0.0, 1.0) * (1.0 - 0.75 * chip_mask)
    crest = t.blur(height, 4.0) - t.blur(height, 30.0)  # broad high ground, not ridge lines
    wear = np.clip(0.35 * smoothstep(0.1, 0.5, -cav_s) + 0.8 * smoothstep(0.2, 1.6, crest + 0.25 * breakup), 0.0, 1.0)
    wear *= 0.55 + 0.45 * smoothstep(-0.6, 0.6, t.band('wear-grain', t.mm, 4.0, 0.0))
    fresh = chip_mask * (1.0 - 0.6 * smoothstep(0.2, 0.8, grime))
    albedo *= (1.0 + spec['wear'] * wear - 0.3 * np.clip(pores * 2.5, 0.0, 1.0))[..., None]
    albedo = albedo * (1.0 - spec['grime_amount'] * grime[..., None] * (1.0 - np.array(spec['grime'], np.float32)))
    albedo = albedo * (1.0 - 0.45 * fresh[..., None]) + np.array(spec['fresh'], np.float32) * (0.45 * fresh[..., None])
    albedo = np.clip(albedo, 0.02, 0.6)
    rough = (spec['roughness'] + 0.14 * grime - 0.16 * wear - 0.08 * fresh
             + 0.05 * t.band('rough-n', t.mm, 6.0, 0.3))
    if minerals:
        rough -= 0.22 * (1.0 - mica - feldspar) * smoothstep(0.6, 0.2, grime) + 0.1 * feldspar
    rough = np.clip(rough, 0.25, 1.0)
    lo, hi = np.percentile(height, [0.05, 99.95])
    return dict(height_mm=height, height_range=(float(lo), float(hi)), albedo=albedo, roughness=rough,
                ao=np.clip(ao, 0.0, 1.0), normal=normals(t, height), pits=pit_count)


# --- image output -------------------------------------------------------------------------

def srgb(linear: np.ndarray) -> np.ndarray:
    linear = np.clip(linear, 0.0, 1.0)
    return np.where(linear <= 0.0031308, linear * 12.92, 1.055 * np.power(linear, 1.0 / 2.4) - 0.055)


def write_png(path: Path, data: np.ndarray, bits: int = 8, srgb_chunk: bool = False) -> None:
    """Deterministic PNG (Sub filter, zlib 6); data in 0..1, top row first."""
    h, w = data.shape[:2]
    channels = 1 if data.ndim == 2 else data.shape[2]
    scale = 255 if bits == 8 else 65535
    q = np.clip(np.round(np.asarray(data, np.float64) * scale), 0, scale).astype('>u1' if bits == 8 else '>u2')
    raw = q.reshape(h, w * channels).view(np.uint8)
    bpp = channels * bits // 8
    sub = raw.copy()
    sub[:, bpp:] = raw[:, bpp:] - raw[:, :-bpp]
    rows = np.concatenate([np.ones((h, 1), np.uint8), sub], axis=1)

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xFFFFFFFF)

    color_type = {1: 0, 3: 2, 4: 6}[channels]
    parts = [b'\x89PNG\r\n\x1a\n', chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, bits, color_type, 0, 0, 0))]
    if srgb_chunk:
        parts.append(chunk(b'sRGB', b'\x00'))
    parts += [chunk(b'IDAT', zlib.compress(rows.tobytes(), 6)), chunk(b'IEND', b'')]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b''.join(parts))


def downsample(img: np.ndarray, factor: int) -> np.ndarray:
    if factor <= 1:
        return img
    h, w = img.shape[:2]
    return img.reshape(h // factor, factor, w // factor, factor, *img.shape[2:]).mean(axis=(1, 3))


def lit(maps: dict, strength: float = 0.75) -> np.ndarray:
    """Quick shading: albedo under a raking neutral light (30 degrees up) and a dim fill, sRGB."""
    nrm = maps['normal'].copy()
    nrm[..., :2] *= strength
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    light = np.array([-0.61, 0.61, 0.5])
    light /= np.linalg.norm(light)
    direct = np.clip(nrm @ light, 0.0, None) * 2.3
    shade = direct + 0.12 * (0.4 + 0.6 * maps['ao'])
    return srgb(maps['albedo'] * shade[..., None])


def seam_score(img: np.ndarray) -> float:
    """How unusual the wrap-around step is among all row and column steps, in standard
    deviations (|z| < 3 is indistinguishable from the interior; a seam scores far higher)."""
    a = np.asarray(img, np.float64)
    a = a if a.ndim == 2 else a.mean(-1)
    worst = 0.0
    for axis in (0, 1):
        steps = np.abs(np.diff(a, axis=axis, append=np.take(a, [0], axis=axis))).mean(axis=1 - axis)
        inner, wrap = steps[:-1], steps[-1]
        worst = max(worst, abs(wrap - inner.mean()) / inner.std())
    return round(float(worst), 2)


def save_maps(directory: Path, maps: dict) -> dict:
    lo, hi = maps['height_range']
    height01 = np.clip((maps['height_mm'] - lo) / (hi - lo), 0.0, 1.0)
    encoded = {
        'albedo': (srgb(maps['albedo']), 8, True),
        'normal_gl': (maps['normal'] * 0.5 + 0.5, 8, False),
        'roughness': (maps['roughness'], 8, False),
        'height': (height01, 16, False),
        'ao': (maps['ao'], 8, False),
    }
    seams = {}
    for name, (data, bits, srgb_chunk) in encoded.items():
        write_png(directory / f'{name}.png', data, bits, srgb_chunk)
        seams[name] = seam_score(data)
    lum = maps['albedo'] @ np.array([0.2126, 0.7152, 0.0722])
    rgb = maps['albedo'].reshape(-1, 3).mean(0)
    return dict(seam_z=seams, height_range_mm=round(hi - lo, 2),
                albedo_linear_mean=[round(float(c), 3) for c in rgb],
                albedo_luminance_p1_p50_p99=[round(float(v), 3) for v in np.percentile(lum, [1, 50, 99])],
                saturation_mean=round(float(((maps['albedo'].max(-1) - maps['albedo'].min(-1)) / maps['albedo'].max(-1)).mean()), 3),
                roughness_mean=round(float(maps['roughness'].mean()), 3),
                ao_mean=round(float(maps['ao'].mean()), 3), pits=maps['pits'])


def tiling_sheet(maps: dict, path: Path, strength: float) -> None:
    """3 x 3 repeats (5.4 m of wall) of the lit tile, at 1/4 resolution."""
    tile = downsample(lit(maps, strength), max(1, maps['albedo'].shape[0] // 512))
    write_png(path, np.tile(tile, (3, 3, 1)), 8, True)


def previews(maps: dict, directory: Path, name: str, strength: float) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    shaded = lit(maps, strength)
    n = shaded.shape[0]
    write_png(directory / f'{name}_lit.png', downsample(shaded, max(1, n // 1024)), 8, True)
    crop = np.roll(shaded, (n // 8, n // 8), (0, 1))[:768, :768]  # straddles the wrap corner
    write_png(directory / f'{name}_crop.png', crop, 8, True)
    write_png(directory / f'{name}_albedo_crop.png', srgb(np.roll(maps['albedo'], (n // 8, n // 8), (0, 1))[:768, :768]), 8, True)


# --- Cycles review ------------------------------------------------------------------------

def use_gpu(scene: bpy.types.Scene) -> str:
    scene.render.engine = 'CYCLES'
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        devices = [d for d in prefs.devices if d.type == 'METAL']
        for d in prefs.devices:
            d.use = d.type == 'METAL'
        if devices:
            scene.cycles.device = 'GPU'
            return 'METAL'
    except (KeyError, TypeError, AttributeError):
        pass
    scene.cycles.device = 'CPU'
    return 'CPU'


class Graph:
    def __init__(self, material: bpy.types.Material):
        self.nodes, self.links = material.node_tree.nodes, material.node_tree.links

    def node(self, kind: str, **props):
        node = self.nodes.new(kind)
        for key, value in props.items():
            setattr(node, key, value)
        return node

    def feed(self, socket, value) -> None:
        if isinstance(value, bpy.types.NodeSocket):
            self.links.new(value, socket)
        else:
            socket.default_value = value

    def math(self, op: str, a, b=0.0, c=0.0):
        node = self.node('ShaderNodeMath', operation=op)
        for socket, value in zip(node.inputs, (a, b, c)):
            self.feed(socket, value)
        return node.outputs[0]

    def vec(self, op: str, a, b=(0.0, 0.0, 0.0), scale: float = None):
        node = self.node('ShaderNodeVectorMath', operation=op)
        self.feed(node.inputs[0], a)
        self.feed(node.inputs[1], b)
        if scale is not None:
            self.feed(node.inputs[3], scale)
        return node.outputs['Value' if op == 'DOT_PRODUCT' else 'Vector']


def review_material(name: str, folder: Path, strength: float, tint=(1.0, 1.0, 1.0), wet_mask: bool = False):
    """Cycles stand-in for dungeon_surface.gdshader: same normal scaling, roughness remap,
    85 % saturation, specular 0.35, AO 0.7 on the indirect share approximated in albedo,
    and the shader's wet darkening/gloss where a world-space damp mask is on."""
    material = bpy.data.materials.new(name)
    g = Graph(material)
    bsdf = g.nodes['Principled BSDF']
    uv = g.node('ShaderNodeUVMap', uv_map='UVMap')

    def image(map_name: str, colorspace: str):
        img = bpy.data.images.load(str(folder / f'{map_name}.png'), check_existing=True)
        img.colorspace_settings.name = colorspace
        node = g.node('ShaderNodeTexImage', image=img, interpolation='Cubic')
        g.links.new(uv.outputs['UV'], node.inputs['Vector'])
        return node.outputs['Color']

    albedo = image('albedo', 'sRGB')
    rough = image('roughness', 'Non-Color')
    ao = image('ao', 'Non-Color')
    nrm = image('normal_gl', 'Non-Color')
    lum = g.vec('DOT_PRODUCT', albedo, (0.2126, 0.7152, 0.0722))
    color = g.vec('ADD', g.vec('SCALE', albedo, scale=0.85), g.vec('SCALE', (1.0, 1.0, 1.0), scale=g.math('MULTIPLY', lum, 0.15)))
    ao_value = g.node('ShaderNodeSeparateColor')
    g.links.new(ao, ao_value.inputs[0])
    occlusion = g.math('MULTIPLY_ADD', ao_value.outputs[0], 0.35, 0.65)
    color = g.vec('SCALE', g.vec('MULTIPLY', color, tint), scale=occlusion)
    split = g.node('ShaderNodeSeparateColor')
    g.links.new(rough, split.inputs[0])
    dry = g.math('MULTIPLY_ADD', split.outputs[0], 0.33, 0.65)
    # Normal: decode, scale xy by normal_strength, rebuild z, re-encode for the Normal Map node.
    d = g.node('ShaderNodeSeparateColor')
    g.links.new(nrm, d.inputs[0])
    x = g.math('MULTIPLY', g.math('MULTIPLY_ADD', d.outputs[0], 2.0, -1.0), strength)
    y = g.math('MULTIPLY', g.math('MULTIPLY_ADD', d.outputs[1], 2.0, -1.0), strength)
    z = g.math('SQRT', g.math('MAXIMUM', g.math('SUBTRACT', 1.0, g.math('ADD', g.math('MULTIPLY', x, x), g.math('MULTIPLY', y, y))), 0.01))
    enc = g.node('ShaderNodeCombineColor')
    for i, value in enumerate((x, y, z)):
        g.links.new(g.math('MULTIPLY_ADD', value, 0.5, 0.5), enc.inputs[i])
    normal_map = g.node('ShaderNodeNormalMap', space='TANGENT', uv_map='UVMap')
    g.links.new(enc.outputs[0], normal_map.inputs['Color'])
    roughness = dry
    if wet_mask:
        coords = g.node('ShaderNodeNewGeometry')
        damp = g.node('ShaderNodeTexNoise', noise_dimensions='3D')
        damp.inputs['Scale'].default_value = 0.9
        damp.inputs['Detail'].default_value = 3.0
        g.links.new(coords.outputs['Position'], damp.inputs['Vector'])
        sep = g.node('ShaderNodeSeparateXYZ')
        g.links.new(coords.outputs['Position'], sep.inputs[0])
        lower = g.math('SUBTRACT', 1.0, g.math('MINIMUM', g.math('MULTIPLY', sep.outputs['Z'], 2.5), 1.0))
        wet = g.math('ADD', g.math('MULTIPLY_ADD', damp.outputs['Fac'], 8.0, -4.3), g.math('MULTIPLY', lower, 1.2))
        wet = g.math('MINIMUM', g.math('MAXIMUM', wet, 0.0), 1.0)
        darken = g.vec('ADD', (1.0, 1.0, 1.0), g.vec('SCALE', (-0.36, -0.32, -0.34), scale=wet))
        color = g.vec('MULTIPLY', color, darken)
        glossy = g.math('MULTIPLY_ADD', split.outputs[0], 0.14, 0.23)
        roughness = g.math('ADD', dry, g.math('MULTIPLY', g.math('SUBTRACT', glossy, dry), wet))
    g.links.new(color, bsdf.inputs['Base Color'])
    g.links.new(roughness, bsdf.inputs['Roughness'])
    g.links.new(normal_map.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Specular IOR Level'].default_value = 0.35
    return material


def flat_material(name: str, color, roughness: float):
    material = bpy.data.materials.new(name)
    bsdf = material.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Roughness'].default_value = roughness
    return material


def project_uvs(mesh: bpy.types.Mesh, matrix) -> None:
    """World-metre UVs in the orientation of dungeon_surface.gdshader's projection (tangent
    horizontal, V up; Blender V up = Godot V down) times surface() density. Each face uses
    its dominant axis, like a box-mapped stone mesh, so rounded arrises do not smear."""
    uv = mesh.uv_layers.new(name='UVMap')
    normal_matrix = matrix.to_3x3().inverted_safe().transposed()
    up = Vector((0.0, 0.0, 1.0))
    for poly in mesh.polygons:
        n = normal_matrix @ poly.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        n = Vector([math.copysign(1.0, n[i]) if i == axis else 0.0 for i in range(3)])
        tangent = Vector((1.0, 0.0, 0.0)) if axis == 2 else up.cross(n)
        bitangent = n.cross(tangent)
        for index in poly.loop_indices:
            p = matrix @ mesh.vertices[mesh.loops[index].vertex_index].co
            uv.data[index].uv = (p.dot(tangent) * DENSITY, p.dot(bitangent) * DENSITY)


def stone_mesh(name: str, half: Vector, radius: float, pillow: float, seed_offset: Vector) -> bpy.types.Mesh:
    """Box-ish dressed stone: rounded arrises, a slightly domed face and gentle irregularity."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=22, use_grid_fill=True)
    for v in bm.verts:
        t = v.co.copy()
        t = Vector([0.55 * c + 0.45 * math.copysign(1.0 - (1.0 - abs(c)) ** 2, c) for c in t])
        p = Vector((t.x * half.x, t.y * half.y, t.z * half.z))
        inner = Vector([max(-h + radius, min(h - radius, c)) for c, h in zip(p, half)])
        offset = p - inner
        if offset.length > 1e-9:
            p = inner + offset.normalized() * radius
        axis = max(range(3), key=lambda i: abs(t[i]))
        others = [i for i in range(3) if i != axis]
        dome = 1.0
        for i in others:
            dome *= max(0.0, 1.0 - (p[i] / half[i]) ** 2)
        direction = Vector((0.0, 0.0, 0.0))
        direction[axis] = math.copysign(1.0, t[axis])
        p += direction * pillow * dome
        p += Vector((noise.noise(p * 3.0 + seed_offset), noise.noise(p * 3.0 + seed_offset + Vector((7.1, 0, 0))),
                     noise.noise(p * 3.0 + seed_offset + Vector((0, 3.3, 0))))) * 0.004
        v.co = p
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    return mesh


def build_wall(seed: int) -> list:
    """About 3.6 x 1.45 m of coursed stones with 10-16 mm joints in front of a mortar bed."""
    r = core.rng(seed, 'wall')
    stones = []
    z = 0.0
    width = 3.6
    while z < 1.45:
        course = r.uniform(0.21, 0.31)
        x = -width / 2 - r.uniform(0.0, 0.3)
        while x < width / 2:
            length = r.uniform(0.3, 0.62)
            joint = r.uniform(0.010, 0.016)
            half = Vector(((length - joint) / 2, r.uniform(0.11, 0.14), (course - joint) / 2))
            mesh = stone_mesh(f'stone{len(stones)}', half, r.uniform(0.006, 0.012), r.uniform(0.003, 0.007),
                              Vector((r.uniform(0, 50), r.uniform(0, 50), r.uniform(0, 50))))
            obj = core.link(bpy.data.objects.new(mesh.name, mesh))
            obj.location = (x + length / 2, half.y + r.uniform(-0.007, 0.004), z + course / 2)
            obj.rotation_euler = (r.uniform(-0.012, 0.012), r.uniform(-0.015, 0.015), r.uniform(-0.01, 0.01))
            stones.append(obj)
            x += length
        z += course
    bpy.context.view_layer.update()
    for obj in stones:
        project_uvs(obj.data, obj.matrix_world)
    bed = bpy.data.meshes.new('mortar')
    bed.from_pydata([(-2.2, 0.03, -0.2), (2.2, 0.03, -0.2), (2.2, 0.03, 1.8), (-2.2, 0.03, 1.8)], [], [(0, 1, 2, 3)])
    mortar = core.link(bpy.data.objects.new('mortar', bed))
    mortar.data.materials.append(flat_material('mortar', (0.05, 0.045, 0.04), 0.95))
    return stones + [mortar]


def build_sphere(name: str, x: float) -> bpy.types.Object:
    """UV sphere sized so its UVs carry whole repeats at density 0.555 (2 around, 1 pole to pole)."""
    radius = 2.0 / (2.0 * math.pi * DENSITY)
    bm = bmesh.new()
    bm.loops.layers.uv.new('UVMap')
    bmesh.ops.create_uvsphere(bm, u_segments=192, v_segments=96, radius=radius, calc_uvs=True)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    uv = mesh.uv_layers['UVMap']
    coords = np.empty(len(uv.data) * 2, np.float32)
    uv.data.foreach_get('uv', coords)
    coords[0::2] *= 2.0
    uv.data.foreach_set('uv', coords)
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = core.link(bpy.data.objects.new(name, mesh))
    obj.location = (x, 0.0, 0.0)
    return obj


def look(camera: bpy.types.Object, eye, target, lens: float) -> None:
    camera.location = eye
    direction = Vector(target) - Vector(eye)
    camera.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    camera.data.lens = lens


def light(name: str, kind: str, color, energy: float, location, size: float = 0.05, target=None):
    data = bpy.data.lights.new(name, kind)
    data.color = color
    data.energy = energy
    data.shadow_soft_size = size
    if kind == 'AREA':
        data.size = size
    obj = core.link(bpy.data.objects.new(name, data))
    obj.location = location
    if target is not None:
        obj.rotation_euler = (Vector(target) - Vector(location)).to_track_quat('-Z', 'Y').to_euler()
    return obj


def render(path: Path, x: int, y: int) -> Path:
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = x, y
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print('STONE render', core.relative(path), flush=True)
    return path


def review(outdir: Path, variants: list, seed: int, samples: int, strength: float, study: str = '') -> list:
    scene = core.empty_scene()
    device = use_gpu(scene)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.exposure = 0.0
    scene.world = bpy.data.worlds.new('Dark')
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.012, 0.013, 0.015, 1.0)
    camera = core.link(bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera')))
    scene.camera = camera
    directory = outdir / 'review'
    directory.mkdir(parents=True, exist_ok=True)
    renders = []
    print('STONE review device', device, flush=True)

    def clear() -> None:
        for obj in list(scene.objects):
            if obj is not camera:
                bpy.data.objects.remove(obj)

    for name in variants:
        folder = outdir / name
        # Sphere: warm torch raking from the upper left, cool fill from the right.
        clear()
        sphere = build_sphere('sphere', 0.0)
        sphere.data.materials.append(review_material(f'{name}_sphere', folder, strength))
        light('torch', 'POINT', (1.0, 0.8, 0.6), 170.0, (-1.35, -0.55, 0.8), 0.04)
        light('fill', 'AREA', (0.6, 0.72, 0.85), 22.0, (1.8, -1.6, -0.3), 1.5, (0, 0, 0))
        look(camera, (0.0, -2.75, 0.25), (0.0, 0.0, 0.0), 70.0)
        renders.append(render(directory / f'{name}_sphere.png', 1200, 1200))
        # Wall: separate stones, joints, raking torch, damp patches low on the wall.
        clear()
        wall = build_wall(seed)
        r = core.rng(seed, 'tints')
        for obj in wall[:-1]:
            shade = r.uniform(0.9, 1.08)
            tint = (shade * r.uniform(0.98, 1.03), shade, shade * r.uniform(0.96, 1.02))
            obj.data.materials.append(review_material(f'{name}_{obj.name}', folder, strength, tint, wet_mask=True))
        light('torch', 'POINT', (1.0, 0.78, 0.56), 190.0, (-1.55, -0.62, 1.55), 0.04)
        light('fill', 'AREA', (0.6, 0.72, 0.85), 40.0, (0.9, -3.2, 1.6), 2.5, (0.0, 0.0, 0.7))
        look(camera, (0.75, -2.45, 0.9), (-0.05, 0.0, 0.68), 42.0)
        renders.append(render(directory / f'{name}_wall.png', 1600, 1000))
    if study:
        # Same stone at three surface() relief values under one warm sun and the cool fill.
        clear()
        for i, value in enumerate(STUDY):
            x = (i - 1) * 1.5
            sphere = build_sphere(f'sphere{i}', x)
            sphere.data.materials.append(review_material(f'{study}_relief{i}', outdir / study, value))
            label = bpy.data.curves.new(f'label{i}', 'FONT')
            label.body = f'relief {value:.2f}'
            label.size = 0.12
            label.align_x = 'CENTER'
            text = core.link(bpy.data.objects.new(f'label{i}', label))
            text.location = (x, -0.6, -0.74)
            text.rotation_euler = (math.radians(90.0), 0.0, 0.0)
            label.materials.append(flat_material('label', (0.6, 0.6, 0.6), 1.0))
        sun = light('sun', 'SUN', (1.0, 0.8, 0.6), 5.0, (-2.6, -2.6, 1.7), 0.02, (0.0, 0.0, 0.0))
        sun.data.angle = math.radians(1.0)
        light('fill', 'AREA', (0.6, 0.72, 0.85), 90.0, (3.5, -3.0, 0.0), 2.5, (0, 0, 0))
        look(camera, (0.0, -6.4, 0.15), (0.0, 0.0, -0.1), 48.0)
        renders.append(render(directory / f'{study}_relief_study.png', 2400, 1000))
    return renders


def main() -> None:
    options = parse()
    outdir = Path(options.outdir).resolve()
    variants = [v for v in (options.only.split(',') if options.only else VARIANTS) if v]
    for v in variants:
        if v not in VARIANTS:
            raise SystemExit(f'unknown variant {v}; choose from {", ".join(VARIANTS)}')
    core.require_blender()
    report_path = outdir / 'stone_surface.json'
    stats = json.loads(report_path.read_text()).get('variants', {}) if report_path.exists() else {}
    files = []
    for name in variants:
        if not options.no_maps:
            maps = synthesize(name, dict(VARIANTS[name]), options.size, options.seed)
            stats[name] = save_maps(outdir / name, maps)
            tiling_sheet(maps, outdir / 'review' / f'{name}_tile3x3.png', options.strength)
            if options.preview:
                previews(maps, Path(options.preview), name, options.strength)
            print('STONE', name, json.dumps(stats[name]), flush=True)
            del maps
        files += [outdir / name / f'{m}.png' for m in MAPS]
    renders = []
    if not options.no_render:
        renders = review(outdir, variants, options.seed, options.samples, options.strength, options.study)
    files = [f for v in VARIANTS for f in (outdir / v / f'{m}.png' for m in MAPS) if f.exists()]
    core.write_report(report_path, dict(
        task='T-180', seed=options.seed, size=options.size, tile_m=TILE_MM / 1000.0, density=DENSITY,
        mm_per_px=round(TILE_MM / options.size, 3), review_normal_strength=options.strength,
        variants={k: stats[k] for k in VARIANTS if k in stats}), files)


if __name__ == '__main__':
    main()
