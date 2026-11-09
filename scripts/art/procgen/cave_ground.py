"""World-continuous earth, mud and shallow water for the excavated passages."""
import math
import bpy
from mathutils import Vector, noise
from . import core

TRANSITIONS = [] # (plan point, stone collar radius)
SPINES = [] # (world-plan start, end, clear half-width, optional earth bias).

def smooth(a, b, value):
    t=max(0.0,min(1.0,(value-a)/(b-a)))
    return t*t*(3-2*t)

def cloud(point, scale, shift=0.0):
    return .5+.5*noise.noise(Vector((point.x*scale+shift,point.y*scale-shift,2.71)),noise_basis='PERLIN_ORIGINAL')

def nearest(point):
    best=float('inf');centre=point.copy();half=2.7;weighted_bias=0.0;total_weight=0.0
    for spine in SPINES:
        a,b,width=spine[:3]
        delta=b-a
        t=max(0.0,min(1.0,(point-a).dot(delta)/max(delta.length_squared,1e-8)))
        at=a+delta*t
        distance=Vector((point.x-at.x,point.y-at.y,0)).length
        weight=1.0/(1.0+distance*distance)**2
        weighted_bias+=weight*(spine[3] if len(spine)>3 else 0.0);total_weight+=weight
        if distance<best:best=distance;centre=at;half=width
    return centre,best,half,weighted_bias/max(total_weight,1e-8)

def transition(point):
    fade=1.0
    for centre,radius in TRANSITIONS:
        fade=min(fade,smooth(radius,radius+2.5,Vector((point.x-centre.x,point.y-centre.y,0)).length))
    return fade

def field(point):
    _,distance,half,bias=nearest(Vector((point.x,point.y,0)))
    bank=smooth(half-.85+(cloud(point,.6,12)-.5)*.7,half+.15,distance) if math.isfinite(distance) else 0.0
    earth=smooth(.43,.64,cloud(point,.17,19.3)+bias+bank*.22)
    pool=smooth(.50,.65,cloud(point,.62,7.1))*smooth(.75,.98,earth)*(1-bank)
    fade=transition(point)
    return earth*fade,pool*fade,bank*fade

def height(point, floor):
    earth,pool,bank=field(point)
    top=-.065+earth*.085+(cloud(point,2.4)-.5)*.016
    top=top*(1-smooth(.18,.5,pool))-.045*smooth(.18,.5,pool)
    return floor+top+bank*(.06+.20*cloud(point,.7,4))

def shape_offset(point, floor):
    centre,distance,_,_=nearest(Vector((point.x,point.y,0)))
    if distance>10:return Vector()
    # Enlarge rather than pinch the walking clearance; coarse excavation is
    # asymmetric along the route, with both roof pockets and wider shoulders.
    radial=Vector((point.x-centre.x,point.y-centre.y,max(0,point.z-floor-1.4)*.65))
    if radial.length<.001:return Vector()
    amount=.2+.45*cloud(point,.21,3.9)
    return radial.normalized()*amount*smooth(.12,1.05,point.z-floor)*transition(point)

def cell(name, x0, x1, y0, y1, floor, water=False):
    steps=1 if water else 3
    vertices=[]
    for y in range(steps+1):
        for x in range(steps+1):
            p=Vector((x0+(x1-x0)*x/steps,y0+(y1-y0)*y/steps,floor))
            p.z=floor-.008 if water else height(p,floor)
            vertices.append(p)
    faces=[]
    for y in range(steps):
        for x in range(steps):
            k=y*(steps+1)+x
            faces.extend([(k,k+1,k+steps+2),(k,k+steps+2,k+steps+1)])
    top_count=len(vertices)
    for vertex in vertices[:]:vertices.append(Vector((vertex.x,vertex.y,floor-.011 if water else floor-.20)))
    top_faces=len(faces)
    faces += [tuple(i+top_count for i in reversed(face)) for face in faces[:]]
    boundary=list(range(steps+1))+[y*(steps+1)+steps for y in range(1,steps+1)]+[steps*(steps+1)+x for x in range(steps-1,-1,-1)]+[y*(steps+1) for y in range(steps-1,0,-1)]
    for a,b in zip(boundary,boundary[1:]+boundary[:1]):faces.append((a,a+top_count,b+top_count,b))
    kind='water' if water else 'earth' 
    mesh=bpy.data.meshes.new('ground_'+kind+'_'+name)
    mesh.from_pydata(vertices,[],faces);mesh.update()
    normals=[]
    for face in mesh.polygons:
        face.use_smooth=face.index<top_faces
        for loop in face.loop_indices:
            p=mesh.vertices[mesh.loops[loop].vertex_index].co
            if face.index<top_faces and not water:
                dx=(height(p+Vector((.01,0,0)),floor)-height(p-Vector((.01,0,0)),floor))/.02
                dy=(height(p+Vector((0,.01,0)),floor)-height(p-Vector((0,.01,0)),floor))/.02
                normals.append(Vector((-dx,-dy,1)).normalized())
            else:normals.append(face.normal)
    mesh.normals_split_custom_set(normals)
    obj=core.link(bpy.data.objects.new(mesh.name,mesh))
    obj['floor_kind']=kind;obj['floor_level']=floor
    obj['tone']=.9;obj['frame']=[1,0,0,0,1,0,0,0,1];obj['natural_floor']=True
    return obj
