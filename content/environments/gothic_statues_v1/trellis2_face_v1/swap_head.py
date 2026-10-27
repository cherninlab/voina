"""Replace the failed full-body head region with the reconstructed close-up."""
import json
from pathlib import Path
import numpy as np
import trimesh

root=Path(__file__).resolve().parent
body=trimesh.load(root.parent/'trellis2_statues_v1/oracle_768/clean_high.glb',force='mesh',process=False)
head=trimesh.load(root/'head_aligned.glb',force='mesh',process=False)
c=body.triangles_center
# Cut only the old facial shell. Keep the crown, horn roots and long hair.
ellipse=((c[:,0]-.028)/.069)**2+((c[:,1]-1.184)/.102)**2
remove=(ellipse<1)&(c[:,2]>.028)
head=head.submesh([head.triangles_center[:,1]>1.09],append=True)
kept=body.submesh([~remove],append=True)
combined=trimesh.util.concatenate([kept,head])
combined.export(root/'oracle_head_swap.glb')
(root/'head_swap.json').write_text(json.dumps({'removed_old_head_triangles':int(remove.sum()),
    'retained_body_triangles':len(kept.faces),'new_head_triangles':len(head.faces),
    'method':'Replace facial shell with close-up head; preserve original crown, horns and long hair; fuse using VDB next'},indent=2)+'\n')
print('HEAD_SWAP_OK',len(combined.faces),flush=True)
