"""Register the close-up head to the full-body face with trimmed ICP."""
import json
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation
import trimesh

ROOT=Path(__file__).resolve().parent
SOURCE=ROOT.parent/'trellis2_statues_v1/oracle_768/clean_high.glb'
body=trimesh.load(SOURCE,force='mesh',process=False)
head=trimesh.load(ROOT/'head_512/clean_high.glb',force='mesh',process=False)
bv=body.vertices.copy();hv=head.vertices.copy()
rng=np.random.default_rng(42)
src=hv[(abs(hv[:,0])<.23)&(hv[:,1]>.58)&(hv[:,1]<1.23)&(hv[:,2]>.17)]
dst=bv[(bv[:,0]>-.035)&(bv[:,0]<.11)&(bv[:,1]>1.105)&(bv[:,1]<1.29)&(bv[:,2]>.095)]
src=src[rng.choice(len(src),min(24000,len(src)),replace=False)]
dst=dst[rng.choice(len(dst),min(45000,len(dst)),replace=False)]
tree=cKDTree(dst);best=None
for yaw in [10,20,30]:
    r=Rotation.from_euler('y',yaw,degrees=True).as_matrix();s=.22
    nose_head=np.array([-.01533436,.90428674,.36325616])
    nose_body=np.array([.063,1.163,.171])
    t=nose_body-nose_head@r.T*s
    for _ in range(45):
        points=src@r.T*s+t;dist,ids=tree.query(points,workers=4)
        keep=dist<np.quantile(dist,.75)
        a=src[keep];b=dst[ids[keep]];ac=a.mean(0);bc=b.mean(0)
        u,values,vt=np.linalg.svd((a-ac).T@(b-bc))
        rr=vt.T@u.T
        if np.linalg.det(rr)<0:vt[-1]*=-1;rr=vt.T@u.T
        ss=np.clip(np.sum(values)/np.sum((a-ac)**2),.20,.25)
        tt=bc-ac@rr.T*ss
        delta=np.linalg.norm(tt-t)+np.linalg.norm(rr-r)
        r,s,t=rr,ss,tt
        if delta<1e-6:break
    d,_=tree.query(src@r.T*s+t,workers=4)
    score=float(np.mean(np.sort(d)[:int(.75*len(d))]))
    if best is None or score<best[0]:best=(score,r,s,t)
score,r,s,t=best
aligned=hv@r.T*s+t
trimesh.Trimesh(aligned,head.faces,process=False).export(ROOT/'head_aligned.glb')
receipt={'method':'trimmed ICP; similarity fit with bounded head scale',
    'trimmed_distance_m':score,'rotation':r.tolist(),'scale':float(s),'translation':t.tolist()}
(ROOT/'head_alignment.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('HEAD_ALIGNMENT_OK',json.dumps(receipt),flush=True)
