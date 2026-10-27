"""Local repair and protected-face regions in the existing GLB coordinates."""
import numpy as np

def face_radius(points):
    return np.sqrt(((points[...,0]-.035)/.071)**2+((points[...,1]-1.194)/.093)**2)

def protected_face(points, radius=1.04):
    return (face_radius(points)<radius)&(points[...,2]>.065)&(points[...,1]<1.252)

def head_region(points):
    return (points[...,1]>1.095)&(abs(points[...,0])<.205)

def facial_depth(vertices,faces,query):
    """Orthographic triangle depth buffer, including broad cheek triangles."""
    from scipy.ndimage import distance_transform_edt
    triangles=vertices[faces]
    lo=triangles[:,:,:2].reshape(-1,2).min(0)-.005
    hi=triangles[:,:,:2].reshape(-1,2).max(0)+.005
    size=1024;scale=(size-1)/(hi-lo)
    depth=np.full((size,size),-np.inf)
    for triangle in triangles:
        p=(triangle[:,:2]-lo)*scale
        lower=np.maximum(np.floor(p.min(0)).astype(int),0)
        upper=np.minimum(np.ceil(p.max(0)).astype(int),size-1)
        if np.any(upper<lower):continue
        xx,yy=np.meshgrid(np.arange(lower[0],upper[0]+1),np.arange(lower[1],upper[1]+1))
        den=(p[1,1]-p[2,1])*(p[0,0]-p[2,0])+(p[2,0]-p[1,0])*(p[0,1]-p[2,1])
        if abs(den)<1e-9:continue
        a=((p[1,1]-p[2,1])*(xx-p[2,0])+(p[2,0]-p[1,0])*(yy-p[2,1]))/den
        b=((p[2,1]-p[0,1])*(xx-p[2,0])+(p[0,0]-p[2,0])*(yy-p[2,1]))/den
        c=1-a-b;inside=(a>=-.0001)&(b>=-.0001)&(c>=-.0001)
        z=a*triangle[0,2]+b*triangle[1,2]+c*triangle[2,2]
        tile=depth[lower[1]:upper[1]+1,lower[0]:upper[0]+1]
        np.maximum(tile,np.where(inside,z,-np.inf),out=tile)
    missing=~np.isfinite(depth)
    near=distance_transform_edt(missing,return_distances=False,return_indices=True)
    depth[missing]=depth[tuple(near[:,missing])]
    ij=np.rint((query[:,:2]-lo)*scale).astype(int)
    covered=np.all((ij>=0)&(ij<size),axis=1);ij=np.clip(ij,0,size-1)
    return depth[ij[:,1],ij[:,0]],covered
