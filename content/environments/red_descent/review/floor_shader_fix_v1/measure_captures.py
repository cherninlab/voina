"""Measure the fixed chapel floor region in output PNG RGB (not linear HDR)."""
from pathlib import Path
from PIL import Image
import hashlib
import json
import statistics

root = Path(__file__).resolve().parent
modes = ["baseline", "no-ao", "no-noise", "flat-texture", "no-grade", "linear-tonemap", "albedo-only", "texture-only", "no-normal", "no-specular", "rough-one", "no-specular-rough-one", "no-shadows", "constant-albedo"]
results = []
baseline = Image.open(root / "baseline/13-chapel-spill.png").convert("RGB")
for mode in modes:
    image = Image.open(root / mode / "13-chapel-spill.png").convert("RGB")
    assert image.size == (1440, 900)
    luminance = sorted((.2126*r + .7152*g + .0722*b) / 255 for r, g, b in image.crop((0, 500, 1440, 900)).getdata())
    results.append({"mode": mode, "region_xyxy": [0, 500, 1440, 900], "mean_display_luminance": statistics.mean(luminance), "p05_display_luminance": luminance[len(luminance)//20], "below_0_025_fraction": sum(x < .025 for x in luminance)/len(luminance), "same_pixels_as_baseline": image.tobytes() == baseline.tobytes(), "png_sha256": hashlib.sha256((root / mode / "13-chapel-spill.png").read_bytes()).hexdigest()})
(root / "display_metrics.json").write_text(json.dumps({"note": "Luminance of output PNG RGB display values, not a linear HDR framebuffer or shader ALBEDO measurement; fixed same-camera chapel floor rectangle includes real joints and shadows.", "results": results}, indent=2) + "\n")
print("SHADER_CAPTURE_MEASURE_OK:", len(results), "modes; 1440x900")
