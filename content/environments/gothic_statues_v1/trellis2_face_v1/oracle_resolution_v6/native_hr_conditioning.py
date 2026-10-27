"""Run the pinned native generator with separate 1024px HR conditioning."""
import hashlib
import json
from pathlib import Path
import sys
import traceback

import mlx.core as mx

native = Path("/Users/theochernin/Projects/CherninLab3D/vendor/trellis2mlx/generate.py")
text = native.read_text()
assert hashlib.sha256(text.encode()).hexdigest() == "4a24bbf9e865685a71d933b16f8f21c7126abe8502740e6ed654f575a65ee3b1", "Native generator changed; inspect before patching"
anchor = "        hr_slat_flow = SLatFlowModel.for_shape()\n"
assert text.count(anchor) == 1, "Native HR anchor changed; inspect before patching"
insert = """        # Same high-resolution image conditioning as the official cascade.
        assert len(image_paths) == 1 and not vs3d_mode
        cond = _extract_image_features(image_paths[0], resolution=1024)
        neg_cond = mx.zeros_like(cond)
        assert cond.shape[1] == 4101
        if args.save_checkpoints:
            from trellmlx.checkpoint import save_checkpoint
            save_checkpoint(args.save_checkpoints, "conditioning_hr",
                            cond=np.array(cond), neg_cond=np.array(neg_cond),
                            image_size=1024)
        print("HR_CONDITIONING_1024_OK", cond.shape, flush=True)

"""
patched = text.replace(anchor, insert+anchor)
argv = sys.argv[1:]
output = Path(argv[argv.index("--output")+1]).parent
requested = int(argv[argv.index("--resolution")+1])
receipt = {"base_generator":str(native),"base_sha256":hashlib.sha256(text.encode()).hexdigest(),
           "patched_sha256":hashlib.sha256(patched.encode()).hexdigest(),
           "patch":"1024px HR image features immediately before HR flow; LR stays 512px",
           "requested_grid":requested,"memory_limit_gib":42,"cache_limit_gib":6,
           "status":"failed"}
mx.set_memory_limit(42*1024**3)
mx.set_cache_limit(6*1024**3)
sys.path.insert(0,str(native.parent))
sys.argv = [str(native),*argv]
try:
    exec(compile(patched,str(native),"exec"),{"__name__":"__main__","__file__":str(native)})
    meta=json.loads((output/"checkpoints/mesh_raw.json").read_text())
    assert meta["mesh_grid_size"]==requested, "Native generator reduced the requested grid"
    receipt.update(status="complete",actual_grid=meta["mesh_grid_size"],
                   peak_mlx_memory_gib=mx.get_peak_memory()/1024**3)
except BaseException as exc:
    receipt.update(error=str(exc),traceback=traceback.format_exc())
    raise
finally:
    (output/"runtime_patch.json").write_text(json.dumps(receipt,indent=2)+"\n")
