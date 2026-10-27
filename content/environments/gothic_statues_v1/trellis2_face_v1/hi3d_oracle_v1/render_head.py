"""Reuse the studio renderer with the full statue's fixed lighting frame."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
reference = root.parent / "oracle_resolution_v6/1536/review/clean_views.json"
bounds = json.loads(reference.read_text())["world_bounds"]
center = [(a + b) / 2 for a, b in zip(*bounds)]
span = max(b - a for a, b in zip(*bounds))
studio_path = root.parent.parent / "e01_crawling_v1/render_review.py"
source = studio_path.read_text()
anchor = "center=(lo+hi)/2;span=max(hi-lo)"
assert source.count(anchor) == 1
source = source.replace(anchor, f"center=Vector({center!r});span={span!r}")
studio = {"__name__": "__main__", "__file__": str(studio_path)}
exec(compile(source, str(studio_path), "exec"), studio)
detail_path = root.parent / "plastic_oracle_v5/render_review.py"
source = detail_path.read_text()
anchor = 'state = runpy.run_path(str(root.parent.parent / "e01_crawling_v1/render_review.py"), run_name="__main__")'
assert source.count(anchor) == 1
source = source.replace(anchor, "state = _fixed_studio")
exec(compile(source, str(detail_path), "exec"),
     {"__name__": "__main__", "__file__": str(detail_path), "_fixed_studio": studio})
(studio["args"].out / "lighting_frame.json").write_text(json.dumps({
    "reference": str(reference), "center": center, "span": span,
    "note": "Same area light locations, powers and sizes as the full TRELLIS.2 statue review"
}, indent=2) + "\n")
