"""Mask the approved four views and run installed joint-image reconstruction paths."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

ROOT=Path(__file__).resolve().parent
CL3D=Path('/Users/theochernin/Projects/CherninLab3D')
OUT=ROOT/'four_view_reconstruction_v1'
NAMES=['front','left','back','right']
os.environ.setdefault('U2NET_HOME',str(CL3D/'models/matting'))
os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK','1')
parser=argparse.ArgumentParser()
parser.add_argument('--method',choices=['prepare','instantmesh','trellis'],required=True)
parser.add_argument('--resolution',type=int,default=256)
parser.add_argument('--seed',type=int,default=42)
parser.add_argument('--steps',type=int,default=50)
parser.add_argument('--trellis-mode',choices=['multidiffusion','stochastic'],default='multidiffusion')
parser.add_argument('--trellis-native-crop',action='store_true')
args=parser.parse_args()
OUT.mkdir(exist_ok=True)

import numpy as np
from PIL import Image,ImageDraw

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def prepare():
    import cv2
    from rembg import new_session,remove
    cv2.setNumThreads(4)
    session=new_session('u2net',providers=['CPUExecutionProvider'])
    inputs=OUT/'inputs';inputs.mkdir(exist_ok=True)
    records=[];sheet=Image.new('RGB',(1800,1900),'#dddcd8');draw=ImageDraw.Draw(sheet)
    for i,name in enumerate(NAMES):
        source=ROOT/'statue_from_rig_v1'/f'{name}.png'
        image=Image.open(source).convert('RGBA')
        mask=remove(image.convert('RGB'),session=session,only_mask=True).convert('L')
        image.putalpha(mask);image.save(inputs/f'{name}_masked.png')
        target=Image.open(ROOT/'female_ik_v4'/f'{name}.png').getchannel('A')
        target_binary=(np.asarray(target)>127).astype(np.float32)
        bbox=mask.point(lambda a:255 if a>127 else 0).getbbox()
        assert bbox is not None,('Empty subject mask',name)
        crop=image.crop(bbox);binary=(np.asarray(crop.getchannel('A'))>127).astype(np.float32)
        scale0=np.sqrt(target_binary.sum()/binary.sum());best=None
        # Register only uniform scale and translation against the matching rig view.
        # No limb warping, rotation, independent horizontal/vertical stretching or repainting.
        for scale in scale0*np.linspace(.65,1.4,36):
            size=(round(crop.width*scale),round(crop.height*scale))
            if min(size)<1 or max(size)>900:continue
            template=cv2.resize(binary,size,interpolation=cv2.INTER_NEAREST)
            match=cv2.matchTemplate(target_binary,template,cv2.TM_CCORR)
            _,intersection,_,point=cv2.minMaxLoc(match)
            iou=intersection/(target_binary.sum()+template.sum()-intersection)
            if best is None or iou>best[0]:best=(float(iou),size,point,float(scale))
        assert best is not None,name
        iou,size,point,scale=best
        assert iou>.45,('Poor rig registration',name,iou)
        canvas=Image.new('RGBA',(900,900),(0,0,0,0))
        canvas.alpha_composite(crop.resize(size,Image.Resampling.LANCZOS),point)
        path=inputs/f'{name}.png';canvas.save(path)
        x=i%2*900;y=i//2*950
        draw.text((x+20,y+15),name.upper()+' / masked and registered to the rig',fill='#202428')
        sheet.paste(canvas,(x,y+50),canvas)
        records.append({'view':name,'source':str(source),'source_sha256':digest(source),
            'input':str(path),'input_sha256':digest(path),'source_mask_bbox':list(bbox),
            'uniform_scale':scale,'crop_placement_xy':list(point),'rig_silhouette_iou':iou})
        print('PREPARED',name,'IoU',round(iou,3),'scale',round(scale,3),flush=True)
    sheet.save(OUT/'input_review.png')
    (OUT/'inputs.json').write_text(json.dumps({'method':'U2Net alpha mask; uniform 2D scale/translation registration to each rig render; original RGB retained',
        'canvas_size':[900,900],'view_order':NAMES,'views':records},indent=2)+'\n')

if args.method=='prepare':prepare();sys.exit(0)
assert (OUT/'inputs.json').exists(),'Run --method prepare first and inspect input_review.png'
paths=[OUT/'inputs'/f'{name}.png' for name in NAMES]
import torch
import trimesh
torch.set_num_threads(4)
assert torch.backends.mps.is_available()
started=time.monotonic()
if args.method=='instantmesh':
    sys.path.insert(0,str(CL3D))
    from web_ui.multiview_shape import MultiViewShape
    print('Loading InstantMesh camera-conditioned four-view model',flush=True)
    model=MultiViewShape.load()
    # Rig front is +Y in the Z-up frame. The camera function measures azimuth from +X.
    azimuths=[90,180,270,0]
    mesh=model.reconstruct(paths,azimuths,resolution=args.resolution,elevation=20,
        progress=lambda s:print(s,flush=True))
    report={'model':'TencentARC/InstantMesh instant_nerf_large',
        'weight_revision':'b785b4ecfb6636ef34a08c748f96f6a5686244d0',
        'method':'all four images encoded jointly with explicit camera conditioning; local MPS NeRF-density extraction adapter',
        'azimuths_degrees':azimuths,'elevation_degrees':20,'resolution':args.resolution,
        'color':'shape only; neutral review material'}
    folder=OUT/f'instantmesh_{args.resolution}'
else:
    os.environ['SPARSE_BACKEND']='pytorch';os.environ['ATTN_BACKEND']='sdpa'
    sys.path.insert(0,str(CL3D/'vendor/trellis-mac-mps'))
    from trellis.pipelines import TrellisImageTo3DPipeline
    print('Loading TRELLIS four-image multidiffusion',flush=True)
    pipe=TrellisImageTo3DPipeline.from_pretrained(str(CL3D/'models/TRELLIS-E01-mesh'))
    pipe.to(torch.device('mps'))
    images=[]
    if args.trellis_native_crop:paths=[OUT/'inputs'/f'{name}_masked.png' for name in NAMES]
    for path in paths:
        image=Image.open(path).convert('RGBA')
        if args.trellis_native_crop:images.append(image)
        else:
            black=Image.new('RGBA',image.size,'black');black.alpha_composite(image)
            images.append(black.convert('RGB').resize((518,518),Image.Resampling.LANCZOS))
    output=pipe.run_multi_image(images,seed=args.seed,formats=['mesh'],preprocess_image=args.trellis_native_crop,
        mode=args.trellis_mode,sparse_structure_sampler_params={'steps':args.steps},
        slat_sampler_params={'steps':args.steps})
    result=output['mesh'][0];assert result.success
    vertices=result.vertices.detach().float().cpu().numpy()
    vertices=vertices[:,[0,2,1]]*np.array([1,1,-1])
    vertices*=2/max(np.ptp(vertices,axis=0))
    colors=result.vertex_attrs[:,:3].detach().float().cpu().numpy()
    rgba=np.column_stack([np.clip(colors*255,0,255).astype(np.uint8),np.full(len(colors),255,np.uint8)])
    mesh=trimesh.Trimesh(vertices,result.faces.detach().cpu().numpy(),vertex_colors=rgba,process=True)
    report={'model':'microsoft/TRELLIS-image-large','weight_revision':'25e0d31ffbebe4b5a97464dd851910efc3002d96',
        'method':'four-image inference using published image checkpoint; no explicit cameras',
        'conditioning_mode':args.trellis_mode,'preprocessing':'native per-image foreground crop' if args.trellis_native_crop else 'rig-registered common framing',
        'seed':args.seed,'structure_steps':args.steps,'shape_steps':args.steps,
        'color':'native decoder per-vertex RGB'}
    suffix=('_'+args.trellis_mode+'_native') if args.trellis_native_crop else ''
    folder=OUT/f'trellis_multi{args.seed}{suffix}'
assert len(mesh.faces)>0 and np.isfinite(mesh.vertices).all()
folder.mkdir(exist_ok=True);mesh.export(folder/'raw.glb',include_normals=True)
components=mesh.split(only_watertight=False)
report.update(device='mps',view_order=NAMES,inputs=[{'path':str(p),'sha256':digest(p)} for p in paths],
    vertices=len(mesh.vertices),triangles=len(mesh.faces),watertight=bool(mesh.is_watertight),
    components=len(components),bounds=mesh.bounds.tolist(),seconds=time.monotonic()-started,
    mesh_sha256=digest(folder/'raw.glb'))
(folder/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print('FOUR_VIEW_RECONSTRUCTION_OK',json.dumps(report),flush=True)
