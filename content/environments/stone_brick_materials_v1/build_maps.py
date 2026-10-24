"""Encode paired ImageGen material studies as periodic map sets using T-180's bakers.

Run in Blender from the repo root: blender -b --python THIS_FILE
The original AI PNGs are immutable inputs. Height is an artistic estimate, not a scan.
"""
import hashlib
import json
import sys
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'scripts/art'))
import build_stone_surface as surface

# Tile width metres, peak-to-peak relief mm, base dry roughness parameter.
PROFILES = {
    '01-chisel-limestone': (1.8, 5.0, 0.72),
    '02-split-bedded-stone': (1.8, 6.0, 0.78),
    '03-drafted-quoin-stone': (1.8, 5.0, 0.76),
    '04-old-terracotta-brick': (0.9, 2.5, 0.80),
    '05-smoke-darkened-brick': (0.9, 2.0, 0.85),
    '06-limewashed-brick': (0.9, 1.5, 0.86),
    '07-worn-floor-limestone': (1.8, 1.8, 0.45),
    '08-salt-weathered-limestone': (1.8, 5.0, 0.85),
    '09-fine-tooled-sandstone': (1.8, 3.0, 0.80),
}


def read_pixels(path: Path) -> np.ndarray:
    image = bpy.data.images.load(str(path), check_existing=False)
    image.colorspace_settings.name = 'Non-Color'
    width, height = image.size
    assert width == height and width > 100, path
    values = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(values)
    bpy.data.images.remove(image)
    return values.reshape(height, width, 4)[::-1, :, :3].copy()


def periodic(image: np.ndarray) -> np.ndarray:
    """Remove only the smooth field responsible for opposite-edge discontinuities.

    Solve the periodic discrete Poisson equation for the boundary mismatch; subtract
    its smooth solution. This preserves fine features and mean, with no mirroring.
    """
    a = np.asarray(image, np.float64)
    scalar = a.ndim == 2
    if scalar:
        a = a[..., None]
    edge = np.zeros_like(a)
    edge[0] = a[-1] - a[0]
    edge[-1] = -edge[0]
    difference = a[:, -1] - a[:, 0]
    edge[:, 0] += difference
    edge[:, -1] -= difference
    height, width = a.shape[:2]
    denominator = (2 * np.cos(2 * np.pi * np.fft.fftfreq(height))[:, None]
                   + 2 * np.cos(2 * np.pi * np.fft.fftfreq(width))[None, :] - 4)
    denominator[0, 0] = 1
    spectrum = np.fft.fft2(edge, axes=(0, 1)) / denominator[..., None]
    spectrum[0, 0] = 0
    result = a - np.fft.ifft2(spectrum, axes=(0, 1)).real
    return (result[..., 0] if scalar else result).astype(np.float32)


def seam_score(image: np.ndarray) -> float:
    a = image[..., None] if image.ndim == 2 else image
    scores = []
    for channel in range(a.shape[2]):
        for axis in (0, 1):
            plane = a[..., channel]
            steps = np.abs(np.diff(plane, axis=axis, append=np.take(plane, [0], axis=axis))).mean(axis=1-axis)
            scores.append(abs(float(steps[-1] - steps[:-1].mean())) / max(float(steps[:-1].std()), 1e-8))
    return round(max(scores), 3)


def self_check() -> None:
    yy, xx = np.mgrid[:64, :64]
    wave = np.sin(xx * 2 * np.pi / 63) + np.cos(yy * 2 * np.pi / 63)
    assert np.max(np.abs(periodic(wave) - wave)) < 1e-5
    ramp = periodic(xx.astype(float))
    assert np.max(np.abs(ramp[:, -1] - ramp[:, 0])) < 1.1
    grid = surface.Torus(64, 183, 'polarity-check')
    normal = surface.normals(grid, xx.astype(float) + yy)
    assert normal[32, 32, 0] < 0 and normal[32, 32, 1] > 0
    assert np.max(np.abs(np.linalg.norm(normal, axis=-1) - 1)) < 1e-6


def main() -> None:
    self_check()
    report = {'task': 'T-183', 'method': 'ImageGen albedo and separately interpreted height; periodic correction, shared T-180 normal and horizon AO encoding',
              'normal_convention': 'OpenGL tangent, +Y toward image top', 'height_is_measured': False,
              'self_check': 'periodic sinusoid/ramp and analytic normal polarity passed', 'materials': {}}
    for name, (tile_m, relief_mm, base_rough) in PROFILES.items():
        color_path = OUT / 'studies' / f'{name}.png'
        height_path = OUT / 'height_inputs' / f'{name}.png'
        color = read_pixels(color_path)
        estimate = read_pixels(height_path).mean(axis=-1)
        assert color.shape[:2] == estimate.shape, name
        n = estimate.shape[0]
        surface.TILE_MM = tile_m * 1000
        grid = surface.Torus(n, 183, name)
        # Mechanical map conditioning only: immutable original AI PNGs stay beside it.
        albedo_srgb = np.clip(periodic(color), 0, 1)
        height = grid.blur(periodic(estimate), 0.7 * grid.mm)
        lo, hi = np.percentile(height, [0.01, 99.99])
        height01 = np.clip((height - lo) / (hi - lo), 0, 1)
        # Normals derive from exactly the same quantised 16-bit height that is delivered.
        height01 = np.round(height01 * 65535) / 65535
        height_mm = height01 * relief_mm
        normals = surface.normals(grid, height_mm)
        ao = surface.horizon_ao(grid, height_mm)
        cavity = np.clip((grid.blur(height_mm, 4.0) - height_mm) / max(relief_mm * 0.08, 0.1), 0, 1)
        wear = np.clip((height01 - 0.35) * 1.5, 0, 1)
        roughness = np.clip(base_rough + 0.10 * cavity - 0.12 * wear, 0.25, 0.98)
        maps = {'albedo': albedo_srgb, 'normal_gl': normals * 0.5 + 0.5,
                'roughness': roughness, 'height': height01, 'ao': ao}
        folder = OUT / 'materials' / name
        records = {}
        for kind, values in maps.items():
            path = folder / f'{kind}.png'
            surface.write_png(path, values, 16 if kind == 'height' else 8, kind == 'albedo')
            records[kind] = {'file': str(path.relative_to(OUT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                             'seam_z': seam_score(values), 'bits': 16 if kind == 'height' else 8}
        # A computed raking-light 3x3 repeat check, not an engine screenshot.
        linear = np.where(albedo_srgb <= 0.04045, albedo_srgb / 12.92, ((albedo_srgb + 0.055) / 1.055) ** 2.4)
        shaded = surface.lit({'albedo': linear, 'normal': normals, 'ao': ao}, 0.65)[::3, ::3]
        surface.write_png(OUT / 'review' / f'{name}_tile3x3.png', np.tile(shaded, (3, 3, 1)), 8, True)
        decoded = np.round(maps['normal_gl'] * 255) / 255 * 2 - 1
        length_error = float(np.max(np.abs(np.linalg.norm(decoded, axis=-1) - 1)))
        assert np.isfinite(normals).all() and np.isfinite(ao).all() and length_error < 0.008
        report['materials'][name] = {'size': [n, n], 'tile_m': tile_m, 'density': 1 / tile_m,
            'height_range_mm': relief_mm, 'recommended_normal_strength': 0.65, 'recommended_relief_m': relief_mm / 1000,
            'roughness_parameter_mean': round(float(roughness.mean()), 4), 'ao_mean': round(float(ao.mean()), 4),
            'normal_unit_max_error_8bit': length_error, 'original_albedo_sha256': hashlib.sha256(color_path.read_bytes()).hexdigest(),
            'original_height_sha256': hashlib.sha256(height_path.read_bytes()).hexdigest(),
            'albedo_periodic_correction_mean_abs': float(np.abs(albedo_srgb - color).mean()),
            'maps': records, 'approval': 'pending', 'height_caveat': 'Artist estimated; major features registered, fine grain can differ. No measured geometry claim.'}
        print('MAP_SET_OK', name, {k: v['seam_z'] for k, v in records.items()}, flush=True)
    (OUT / 'materials.json').write_text(json.dumps(report, indent=2) + '\n')
    print('MATERIAL_MAPS_OK: 9 sets, 45 maps; original AI inputs preserved', flush=True)


if __name__ == '__main__':
    main()
