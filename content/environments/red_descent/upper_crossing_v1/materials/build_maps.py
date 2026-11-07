"""Prepare the local Krea material family for the existing dungeon shader.

CherninLab3D's Python environment supplies numpy, scipy and Pillow. Height,
normal, roughness and AO are conservative image-derived estimates, not measured PBR.
"""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent


def periodic(image):
    """Remove low-frequency edge mismatch with periodic-plus-smooth decomposition."""
    rows, cols = image.shape[:2]
    boundary = np.zeros_like(image)
    boundary[0] = image[-1] - image[0]
    boundary[-1] = -boundary[0]
    boundary[:, 0] += image[:, -1] - image[:, 0]
    boundary[:, -1] -= image[:, -1] - image[:, 0]
    denominator = 2 * np.cos(2 * np.pi * np.arange(rows) / rows)[:, None] + 2 * np.cos(2 * np.pi * np.arange(cols) / cols)[None, :] - 4
    denominator[0, 0] = 1
    smooth = np.fft.fft2(boundary, axes=(0, 1)) / denominator[:, :, None]
    smooth[0, 0] = 0
    return image - np.fft.ifft2(smooth, axes=(0, 1)).real


def save(path, data):
    pixels = np.uint8(np.clip(data, 0, 1) * 255 + 0.5)
    Image.fromarray(pixels).save(path)


report = {"model": "Krea 2 Turbo Q8 local MLX",
          "license": {"name": "Krea 2 Community License", "url": "https://huggingface.co/krea/Krea-2-Turbo", "acceptance": "User confirmed on 2026-11-07 in the local setup chat"},
          "runtime": {"mflux": "0.24.0", "mlx": "0.32.4", "offline": True}, "model_revision": "9a6edbc94ab786c8b9511247b07ad628c73dc91c", "seed": 186, "steps": 8, "lora": None,
          "maps": "Albedo from generated images, periodic edge correction and shared grey-green grade. Other channels are image-derived estimates.", "surfaces": {}}
for name, target, amplitude in [("bedrock", (0.34, 0.35, 0.32), 0.18), ("limestone", (0.48, 0.49, 0.45), 0.08), ("plaster", (0.43, 0.44, 0.40), 0.10)]:
    source = ROOT / "source" / (name + ".png")
    image = np.array(Image.open(source).convert("RGB"), dtype=np.float64) / 255
    image = periodic(image)
    luma = image @ [0.2126, 0.7152, 0.0722]
    # Match material value/chroma without introducing directional lighting.
    detail = image - luma[:, :, None]
    contrast = {"bedrock": 0.6, "limestone": 0.3, "plaster": 0.35}[name]
    value = np.clip(1 + (luma / np.median(luma) - 1) * contrast, 0.78, 1.22)
    albedo = value[:, :, None] * np.array(target) + detail * 0.4
    out = ROOT / name
    out.mkdir(exist_ok=True)
    save(out / "albedo.png", albedo)
    relief = ndimage.gaussian_filter(luma, 1.2, mode="wrap") - ndimage.gaussian_filter(luma, 20, mode="wrap")
    relief = np.clip(relief / max(np.std(relief) * 5, 0.001), -0.5, 0.5)
    height = 0.5 + relief * 0.5
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 10 * amplitude
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 10 * amplitude
    normal = np.stack((-dx, dy, np.ones_like(dx)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    save(out / "normal_gl.png", normal * 0.5 + 0.5)
    save(out / "height.png", height)
    save(out / "roughness.png", 0.85 - relief * 0.12)
    save(out / "ao.png", np.clip(0.96 + relief * 0.08, 0.88, 1))
    save(out / "metallic.png", np.zeros_like(luma))
    seam = np.concatenate(((albedo[0] - albedo[-1]).ravel(), (albedo[:, 0] - albedo[:, -1]).ravel()))
    adjacent = np.concatenate((np.diff(albedo, axis=0).ravel(), np.diff(albedo, axis=1).ravel()))
    ratio = float(np.mean(np.abs(seam)) / np.mean(np.abs(adjacent)))
    assert ratio < 1.5, (name, ratio)
    report["surfaces"][name] = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "edge_vs_adjacent_mean_difference": ratio,
                                "maps_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.glob("*.png"))}}
(ROOT / "provenance.json").write_text(json.dumps(report, indent=2) + "\n")
print("KREA_MATERIALS_PREPARED", json.dumps(report), flush=True)
