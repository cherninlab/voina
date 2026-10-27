"""Try the pinned Hi3D community demo on the preserved oracle mesh and image."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import time

from gradio_client import Client, handle_file
from huggingface_hub import get_token

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--attempt", choices=["1024", "head_1024"], default="1024")
args = parser.parse_args()
request_path = root / ("head_request.json" if args.attempt == "head_1024" else "request.json")
request = json.loads(request_path.read_text())
out = root / args.attempt
out.mkdir(exist_ok=True)
assert not (out / "receipt.json").exists(), "Existing attempt preserved"
report = dict(request, status="connecting")
started = time.monotonic()


def save():
    report["wall_seconds"] = time.monotonic() - started
    (out / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")


try:
    image, mesh = root / request["image"], root / request["coarse_mesh"]
    for path, key in ((image, "image_sha256"), (mesh, "coarse_sha256")):
        assert hashlib.sha256(path.read_bytes()).hexdigest() == request[key]
    save()
    client = Client(request["space"], token=get_token(), verbose=False,
                    download_files=str(out / "downloads"), analytics_enabled=False)
    assert client.config.get("root") is not None
    (out / "api.json").write_text(json.dumps(client.view_api(return_format="dict", print_info=False), indent=2) + "\n")
    report["status"] = "uploading_and_submitting"
    save()
    job = client.submit(image=handle_file(str(image)), coarse_mesh_file=handle_file(str(mesh)),
                        resolution=request["resolution"], steps=request["steps_per_pass"],
                        seed=request["seed"], remove_bg=request["remove_bg"], api_name="/refine")
    previous = None
    while not job.done():
        status = job.status()
        state = {"code": str(status.code), "rank": status.rank,
                 "queue_size": status.queue_size,
                 "progress": [str(p) for p in (status.progress_data or [])]}
        if state != previous:
            report.update(status="queued_or_running", progress=state)
            save()
            print(json.dumps(state), flush=True)
            previous = state
        time.sleep(3)
    result = job.result()
    (out / "response.json").write_text(json.dumps(result, indent=2) + "\n")
    mesh_result, image_result, info = result
    shutil.copy2(mesh_result, out / "hi3d.glb")
    image_path = image_result["path"] if isinstance(image_result, dict) else image_result
    shutil.copy2(image_path, out / "model_input.png")
    assert info["resolution"] == request["resolution"], "Unexpected output grid"
    report.update(status="complete", run_info=info,
                  output_sha256=hashlib.sha256((out / "hi3d.glb").read_bytes()).hexdigest())
except BaseException as exc:
    report.update(status="failed", error=f"{type(exc).__name__}: {exc}")
    print(report["error"], flush=True)
    raise
finally:
    save()
print("HI3D_REFINEMENT_COMPLETE", json.dumps(report.get("run_info")), flush=True)
