"""Compare fixed floor output-PNG regions; not raw ALBEDO or linear HDR."""
from pathlib import Path
from PIL import Image
import json
import statistics
import sys

root = Path(__file__).resolve().parent
mode = sys.argv[1] if len(sys.argv) > 1 else "material-calibration"
assert mode in ["material-calibration", "production"]
regions = {"13-chapel-spill": [0, 500, 1440, 900], "10-restraint-frame": [0, 650, 1440, 900], "04-broken-nave": [0, 700, 1440, 900]}
results = []
for view, region in regions.items():
    result = {"view": view, "roi_xyxy": region}
    for sample in ["baseline", mode]:
        image = Image.open(root / sample / (view + ".png")).convert("RGB")
        assert image.size == (1440, 900)
        values = sorted((.2126*r + .7152*g + .0722*b)/255 for r, g, b in image.crop(region).getdata())
        result[sample] = {"mean_display_luminance": statistics.mean(values), "p05_display_luminance": values[len(values)//20], "below_0_025_fraction": sum(v < .025 for v in values)/len(values), "below_0_05_fraction": sum(v < .05 for v in values)/len(values)}
    results.append(result)
report = {"note": "PNG output RGB luminance; not linear HDR or raw ALBEDO. Fixed floor rectangles include joints/shadows and some shared props. Same camera poses and default light/shadow updater; small flame flicker can vary scene lighting.", "comparison_mode": mode, "settings": {"tint": [.88, .85, .80], "variation": .14, "ao_albedo": .25, "grime": .15}, "runtime_override_candidate": mode == "material-calibration", "results": results}
(root / ("production_metrics.json" if mode == "production" else "calibration_metrics.json")).write_text(json.dumps(report, indent=2) + "\n")
print("FLOOR_CALIBRATION_MEASURE_OK:", len(results), "same-camera comparisons;", mode)
