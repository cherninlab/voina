"""Pose the existing CC0 female game rig with length-preserving two-bone IK."""
from pathlib import Path
import hashlib
import json
import math
import bpy
from mathutils import Matrix, Vector

root=Path(__file__).resolve().parent
out=root/'female_ik_v4';out.mkdir(exist_ok=True)
source=root.parents[2]/'characters/quaternius/Superhero_Female_FullBody.gltf'
assert source.exists(),source
controls=json.loads((root/'female_ik_v4/pose_controls.json').read_text())
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(source))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
rig.rotation_mode='XYZ'
rig.rotation_euler.z=math.pi
if rig.animation_data:rig.animation_data_clear()
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
rest={b.name:rig.matrix_world@b.matrix for b in rig.pose.bones}
lengths={b.name:b.bone.length for b in rig.pose.bones}
inv=rig.matrix_world.inverted()

def update():bpy.context.view_layer.update()
def head(name):return rig.matrix_world@rig.pose.bones[name].head
def tail(name):return rig.matrix_world@rig.pose.bones[name].tail

def rotate_world(name,axis,degrees):
    bone=rig.pose.bones[name];matrix=rig.matrix_world@bone.matrix
    point=matrix.translation.copy()
    matrix=Matrix.Translation(point)@Matrix.Rotation(math.radians(degrees),4,axis)@Matrix.Translation(-point)@matrix
    bone.matrix=inv@matrix;update()

def align(name,start,end):
    bone=rig.pose.bones[name];current=rig.matrix_world@bone.matrix
    direction=(end-start).normalized()
    rotation=(current.to_quaternion()@Vector((0,1,0))).rotation_difference(direction)@current.to_quaternion()
    bone.matrix=inv@Matrix.LocRotScale(start,rotation,Vector((1,1,1)));update()

def two_bone(start,target,pole,a,b,min_bend=5,max_bend=150):
    direction=target-start;distance=direction.length
    low=math.sqrt(a*a+b*b+2*a*b*math.cos(math.radians(max_bend)))
    high=math.sqrt(a*a+b*b+2*a*b*math.cos(math.radians(min_bend)))
    assert low-1e-6<=distance<=high+1e-6,('Unreachable/unsafe IK target',distance,low,high)
    direction.normalize()
    bend=pole-start; bend-=direction*bend.dot(direction)
    assert bend.length>1e-5,'Pole cannot be collinear with limb'
    bend.normalize()
    along=(a*a-b*b+distance*distance)/(2*distance)
    joint=start+direction*along+bend*math.sqrt(max(0,a*a-along*along))
    return joint

pelvis=rig.pose.bones['pelvis']
matrix=rig.matrix_world@pelvis.matrix;matrix.translation=Vector(controls['pelvis_position'])
pelvis.matrix=inv@matrix;update()
for name,axis,angle in controls['body_rotations_degrees']:rotate_world(name,axis,angle)
print('FK_SPINE',[(name,list(head(name)),list(tail(name))) for name in ['pelvis','spine_01','spine_02','spine_03','upperarm_r']],flush=True)

targets={name:Vector(value) for name,value in controls['ankle_targets'].items()}
for side in ['l','r']:
    upper='thigh_'+side;lower='calf_'+side
    start=head(upper);target=targets['foot_'+side]
    pole=Vector(controls['poles'][lower])
    joint=two_bone(start,target,pole,lengths[upper],lengths[lower],90,155)
    align(upper,start,joint);align(lower,joint,target)

start=head('upperarm_l');targets['hand_l']=start+Vector(controls['reach_wrist_offset'])
start_r=head('upperarm_r');offset=controls['support_wrist_offset_xy']
targets['hand_r']=Vector((start_r.x+offset[0],start_r.y+offset[1],controls['support_wrist_height']))
print('ARM_REACH',list(start_r),list(targets['hand_r']),(targets['hand_r']-start_r).length,
    lengths['upperarm_r']+lengths['lowerarm_r'],flush=True)
for side in ['l','r']:
    upper='upperarm_'+side;lower='lowerarm_'+side
    start=head(upper);target=targets['hand_'+side]
    joint=two_bone(start,target,Vector(controls['poles'][lower]),lengths[upper],lengths[lower],5,150)
    align(upper,start,joint);align(lower,joint,target)

def orient_frame(name,forward,side_direction):
    bone=rig.pose.bones[name];matrix=rig.matrix_world@bone.matrix
    f0=(tail(name)-head(name)).normalized()
    side_direction=side_direction.copy()
    if name.startswith('hand'):
        suffix=name[-1]
        s0=(head('index_01_'+suffix)-head('pinky_01_'+suffix))
    else:
        local_side=rest[name].to_3x3().inverted()@Vector((1,0,0))
        s0=matrix.to_3x3()@local_side
    s0=(s0-f0*s0.dot(f0)).normalized()
    f=forward.normalized();s=(side_direction-f*side_direction.dot(f)).normalized()
    frame0=Matrix((s0,f0,s0.cross(f0))).transposed()
    frame=Matrix((s,f,s.cross(f))).transposed()
    rotation=frame@frame0.transposed()
    point=matrix.translation.copy();matrix.translation=Vector((0,0,0))
    matrix=Matrix.Translation(point)@rotation.to_4x4()@matrix
    bone.matrix=inv@matrix;update()

orient_frame('hand_r',Vector((0,1,0)),Vector((-1,0,0)))
orient_frame('hand_l',Vector((0,.65,.76)),Vector((1,0,0)))
# The source's hanging thumb needs to spread into the supporting palm plane.
for name in ['thumb_01_r','thumb_02_r','thumb_03_r']:
    start=head(name);direction=tail(name)-start;direction.z=0
    align(name,start,start+direction.normalized()*lengths[name])
for side in ['l','r']:
    foot='foot_'+side;ball='ball_'+side
    # Kneeling feet point back; roll their tops toward the floor.
    orient_frame(foot,Vector((0,-1,-.12)),Vector((1,0,0)))
    orient_frame(ball,Vector((0,-1,0)),Vector((1,0,0)))

colors={'ivory':(.65,.58,.47,1),'blue':(.02,.11,.62,1),'teal':(.015,.5,.52,1),
    'coral':(.8,.12,.09,1),'ochre':(.65,.35,.04,1),'violet':(.4,.12,.65,1)}
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name!='Icosphere']
for obj in meshes:
    for modifier in obj.modifiers:
        if modifier.type=='ARMATURE':modifier.use_deform_preserve_volume=True
update()
body=next(o for o in meshes if o.name.startswith('Superhero'))
evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
skin=evaluated.to_mesh()
regions={}
for vertex in body.data.vertices:
    group=max(vertex.groups,key=lambda g:g.weight) if vertex.groups else None
    name=body.vertex_groups[group.group].name if group else ''
    point=evaluated.matrix_world@skin.vertices[vertex.index].co
    regions.setdefault(name,[]).append(point.z)
floor_offset=-min(z for points in regions.values() for z in points)
evaluated.to_mesh_clear()
# Move the complete pose once, preserving all joint angles and target offsets.
matrix=pelvis.matrix.copy();matrix.translation.z+=floor_offset;pelvis.matrix=matrix;update()
for target in targets.values():target.z+=floor_offset
contact_groups={'supporting_palm':['hand_r'], 'left_knee':['calf_l'],
    'right_knee':['calf_r'], 'left_foot':['foot_l','ball_l'], 'right_foot':['foot_r','ball_r']}
contacts={part:min(z+floor_offset for bone in bones for z in regions[bone])
    for part,bones in contact_groups.items()}
assert max(contacts.values())<.025,('Contact floats more than 2.5 cm',contacts)
assert min(contacts.values())>=-1e-5,('Floor penetration',contacts)

for obj in meshes:
    if obj.name.startswith('Superhero'):
        # glTF viewers use COLOR_0; discard the source's unused white color layers.
        for old in list(obj.data.color_attributes):obj.data.color_attributes.remove(old)
        attr=obj.data.color_attributes.new(name='PoseRegions',type='FLOAT_COLOR',domain='POINT')
        for vertex in obj.data.vertices:
            group=max(vertex.groups,key=lambda g:g.weight) if vertex.groups else None
            name=obj.vertex_groups[group.group].name if group else ''
            color='ivory'
            if name=='pelvis':color='blue'
            if any(t in name for t in ['thigh','calf','foot','ball']):color='violet' if name.endswith('_l') else 'ochre'
            if any(t in name for t in ['arm','hand','thumb','index','middle','ring','pinky']):color='teal' if name.endswith('_l') else 'coral'
            attr.data[vertex.index].color=colors[color]
        mat=bpy.data.materials.new('Anatomical region guide');mat.use_nodes=True
        nodes=mat.node_tree.nodes;bsdf=nodes.get('Principled BSDF')
        vertex=nodes.new('ShaderNodeVertexColor');vertex.layer_name=attr.name
        mat.node_tree.links.new(vertex.outputs['Color'],bsdf.inputs['Base Color'])
        bsdf.inputs['Roughness'].default_value=.72
        obj.data.materials.clear();obj.data.materials.append(mat)
        modifier=obj.modifiers.new('Smooth source silhouette','SUBSURF');modifier.levels=1;modifier.render_levels=1
    for poly in obj.data.polygons:poly.use_smooth=True

report={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'source_license':'CC0-1.0, Quaternius Universal Base Characters',
    'method':'analytic two-bone IK, original bone lengths, pole-controlled bend planes, no stretch',
    'targets':{},'joints':{},'bone_length_max_error':0.0,'skin_contact_clearance_m':contacts,
    'floor_offset_m':floor_offset,'joint_bends_degrees':{}}
for name,target in targets.items():
    error=(head(name)-target).length
    report['targets'][name]={'target':list(target),'actual':list(head(name)),'error_m':error}
    assert error<.001,(name,error)
for name in ['thigh_l','thigh_r','calf_l','calf_r','upperarm_l','upperarm_r','lowerarm_l','lowerarm_r']:
    err=abs((tail(name)-head(name)).length-lengths[name])
    report['bone_length_max_error']=max(report['bone_length_max_error'],err)
    report['joints'][name]={'head':list(head(name)),'tail':list(tail(name)),'length':lengths[name]}
    assert err<.0001,(name,err)
for side in ['l','r']:
    for label,upper,lower,low,high in [('knee','thigh_','calf_',90,155),('elbow','upperarm_','lowerarm_',5,150)]:
        a=(tail(upper+side)-head(upper+side)).normalized()
        b=(tail(lower+side)-head(lower+side)).normalized()
        bend=math.degrees(a.angle(b))
        assert low-.01<=bend<=high+.01,(label,side,bend)
        report['joint_bends_degrees'][label+'_'+side]=bend
(out/'ik_checks.json').write_text(json.dumps(report,indent=2)+'\n')

bpy.ops.mesh.primitive_plane_add(size=20);ground=bpy.context.object;ground.name='Review floor'
mat=bpy.data.materials.new('Floor');mat.diffuse_color=(.065,.065,.065,1);ground.data.materials.append(mat)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.world.color=(.15,.15,.15);scene.view_settings.view_transform='AgX'
for point,power in [((2,3,5),550),((-3,-2,4),350)]:
    light=bpy.data.lights.new('Softbox','AREA');light.energy=power;light.shape='DISK';light.size=4
    obj=bpy.data.objects.new('Softbox',light);scene.collection.objects.link(obj);obj.location=point
    obj.rotation_euler=(Vector((0,.12,.55))-obj.location).to_track_quat('-Z','Y').to_euler()
camera=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));scene.collection.objects.link(camera);scene.camera=camera
camera.data.type='ORTHO';camera.data.ortho_scale=1.8;target=Vector((0,.12,.51))
views=[]
for name,az in [('front',0),('left',90),('back',180),('right',270),('hero',315)]:
    ground.hide_render=name!='hero';scene.render.film_transparent=name!='hero'
    a=math.radians(az);e=math.radians(20)
    camera.location=target+Vector((-math.sin(a)*math.cos(e),math.cos(a)*math.cos(e),math.sin(e)))*4
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    views.append({'name':name,'azimuth_degrees_from_positive_y':az,'elevation_degrees':20,
        'camera_world':list(camera.location),'target_world':list(target),
        'projection':'orthographic','orthographic_scale':camera.data.ortho_scale,
        'rgba':name!='hero','file':name+'.png'})
    scene.render.filepath=str((out/f'{name}.png').resolve());bpy.ops.render.render(write_still=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str((out/'female_ik_pose.blend').resolve()),compress=True)
# Bake the evaluated skin for a portable, static GLB; retain the editable rig in the blend.
bpy.ops.object.select_all(action='DESELECT')
for obj in meshes:
    data=bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()),
        preserve_all_data_layers=True,depsgraph=bpy.context.evaluated_depsgraph_get())
    baked=bpy.data.objects.new(obj.name+'_posed',data);scene.collection.objects.link(baked)
    baked.matrix_world=obj.matrix_world.copy();baked.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out/'female_ik_pose.glb'),use_selection=True,
    export_format='GLB',export_animations=False,export_skins=False)
(out/'cameras.json').write_text(json.dumps(views,indent=2)+'\n')
print('FEMALE_IK_GUIDE_OK',flush=True)
