"""Build the original, standalone cultist mesh, deform rig, and inspection clips.

Run with Blender:
  blender --background --python scripts/art/build_hooded_cultist.py
Optional arguments after --: --no-render, --render-only, --samples 48.
Uses the repository's existing CC0 Quaternius male human and original garments.
No downloads or add-ons are required.
Blender coordinates: metres, Z up, -Y forward. glTF: Y up, +Z forward.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Euler, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "content/mobs/hooded_cultist"
TAU = math.tau
ASSETS: list[bpy.types.Object] = []
BASE_MESHES: list[bpy.types.Object] = []
RIG: bpy.types.Object


def blend_weights(a: str, b: str, t: float) -> dict[str, float]:
    t = max(0.0, min(1.0, t))
    return {a: 1.0 - t, b: t} if a != b else {a: 1.0}


def material(name: str, color: tuple[float, ...], roughness: float = 0.8) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color[:3], 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color[:3], 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def fabric_material() -> bpy.types.Material:
    """Packed, UV-based linen albedo/roughness: identical in Blender and glTF."""
    size = 1024
    v, u = np.mgrid[0:size, 0:size].astype(np.float32) / size
    rng = np.random.default_rng(107)
    noise = rng.random((size, size)).astype(np.float32)
    broad = (np.sin(u * 37 + np.sin(v * 26)) * np.sin(v * 43)
             + 0.5 * np.cos(u * 91 + v * 29))
    weave = np.sin(u * TAU * 256) * 0.021 + np.sin(v * TAU * 384) * 0.018
    dirt = np.exp(-v * 13) * (0.75 + 0.25 * np.sin(u * 75 + v * 22))
    shade = np.clip(0.90 + broad * 0.045 + weave + (noise - .5) * .065 - dirt * .40, 0, 1)
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:, :, :3] = shade[:, :, None] * np.array([0.73, 0.65, 0.49], dtype=np.float32)
    # Pixel values are encoded sRGB. The exported image preserves this color space.
    img = bpy.data.images.new("Cultist_Linen_Albedo", size, size)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    mat = material("Unbleached linen | dirt at hem", (.61, .51, .35))
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.location = (-480, 160)
    bsdf = nodes.get("Principled BSDF")
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    # A real tangent-space normal image supplies the tiny cloth weave in the export.
    normals = np.ones((size, size, 4), dtype=np.float32)
    nx = np.sin(u * TAU * 256) * .16
    ny = np.sin(v * TAU * 384) * .13
    nz = np.sqrt(1 - nx * nx - ny * ny)
    normals[:, :, 0] = nx * .5 + .5
    normals[:, :, 1] = ny * .5 + .5
    normals[:, :, 2] = nz * .5 + .5
    normal_img = bpy.data.images.new("Cultist_Linen_Normal", size, size)
    normal_img.colorspace_settings.name = "Non-Color"
    normal_img.pixels.foreach_set(normals.ravel())
    normal_img.pack()
    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.image = normal_img
    normal_tex.location = (-480, -160)
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = .40
    normal_map.location = (-200, -100)
    mat.node_tree.links.new(normal_tex.outputs["Color"], normal_map.inputs["Color"])
    mat.node_tree.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def mesh_object(name: str, verts: list, faces: list, mat: bpy.types.Material,
                weights: list[dict[str, float]], uvs: list | None = None) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    if uvs:
        layer = mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            # Duplicate the U coordinate across the cylindrical wrap seam.
            values = [uvs[mesh.loops[i].vertex_index] for i in poly.loop_indices]
            crosses = max(uv[0] for uv in values) - min(uv[0] for uv in values) > .5
            for loop, uv in zip(poly.loop_indices, values):
                layer.data[loop].uv = (uv[0] + (1 if crosses and uv[0] < .5 else 0), uv[1])
    for i, weights_here in enumerate(weights):
        total = sum(weights_here.values())
        assert total > 0, (name, i)
        for bone, weight in weights_here.items():
            if weight <= .00001:
                continue
            group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
            group.add([i], weight / total, "REPLACE")
    ASSETS.append(obj)
    return obj


def apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def thickness(obj: bpy.types.Object, value: float = .004) -> None:
    mod = obj.modifiers.new("Sewn cloth thickness", "SOLIDIFY")
    mod.thickness = value
    mod.offset = 0
    apply_modifier(obj, mod)


def tube(name: str, points: list, radii: list, mat: bpy.types.Material,
         weights: list[dict[str, float]], sides: int = 10,
         v_range: tuple[float, float] = (.3, .9), caps: bool = True) -> bpy.types.Object:
    verts, faces, uv, skin = [], [], [], []
    for i, point in enumerate(points):
        point = Vector(point)
        direction = Vector(points[min(i + 1, len(points) - 1)]) - Vector(points[max(0, i - 1)])
        direction.normalize()
        a = direction.cross(Vector((0, 1, 0)))
        if a.length < .01:
            a = direction.cross(Vector((1, 0, 0)))
        a.normalize()
        b = direction.cross(a).normalized()
        r = radii[i]
        rx, ry = r if isinstance(r, tuple) else (r, r)
        for j in range(sides):
            angle = TAU * j / sides
            verts.append(point + a * (math.cos(angle) * rx) + b * (math.sin(angle) * ry))
            uv.append((j / sides, v_range[0] + (v_range[1] - v_range[0]) * i / (len(points) - 1)))
            skin.append(weights[i])
        if i:
            for j in range(sides):
                faces.append(((i - 1) * sides + j, (i - 1) * sides + (j + 1) % sides,
                              i * sides + (j + 1) % sides, i * sides + j))
    if caps:
        faces.append(tuple(reversed(range(sides))))
        faces.append(tuple((len(points) - 1) * sides + j for j in range(sides)))
    return mesh_object(name, verts, faces, mat, skin, uv)


def ellipsoid(name: str, center: tuple, scale: tuple, mat: bpy.types.Material,
              bone: str, segments: int = 20, rings: int = 12) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1, "REPLACE")
    ASSETS.append(obj)
    return obj


def torso_weights(z: float) -> dict[str, float]:
    if z < 1.03:
        return {"pelvis": 1}
    if z < 1.16:
        return blend_weights("pelvis", "spine_01", (z - 1.03) / .13)
    if z < 1.30:
        return blend_weights("spine_01", "spine_02", (z - 1.16) / .14)
    if z < 1.42:
        return blend_weights("spine_02", "spine_03", (z - 1.30) / .12)
    return {"spine_03": 1}


def skirt_weights(theta: float, z: float) -> dict[str, float]:
    left = max(0, min(1, .5 + math.sin(theta)*1.4))
    leg = max(0, min(.3, (1.0-z)/.70))  # the hem sways with the stride without tearing open
    return {"pelvis": 1-leg, "thigh_l": leg*left, "thigh_r": leg*(1-left)}


def make_body(linen: bpy.types.Material, seam: bpy.types.Material) -> None:
    """Continuous gown, shaped with broad gravity folds and tighter waist gathers."""
    profile = [
        (.115, .435, .305), (.16, .43, .300), (.24, .414, .29),
        (.34, .39, .278), (.46, .361, .263), (.58, .332, .244),
        (.70, .304, .222), (.81, .276, .204), (.91, .246, .183),
        (1.00, .208, .157), (1.045, .186, .141), (1.075, .184, .14),
        (1.11, .212, .157), (1.18, .222, .164), (1.27, .241, .176),
        (1.36, .266, .178), (1.43, .286, .163), (1.49, .283, .143),
        (1.535, .222, .123), (1.57, .135, .105), (1.585, .098, .09),
    ]
    sides = 64
    verts, faces, skin, uv = [], [], [], []
    for i, (z, rx, ry) in enumerate(profile):
        for j in range(sides):
            theta = j / sides * TAU
            broad = math.sin(12 * theta + .28 * math.sin(z * 5 + theta))
            small = .35 * math.sin(24 * theta - z * 4)
            amp = .010 + .027 * max(0, (1.07 - z) / .95)
            if 1.09 < z < 1.4:
                amp = .012 + .007 * math.sin((z-1.09) / .31 * math.pi)
            fold = amp * (broad + small)
            hem = (.011 * math.sin(theta * 7) + .007 * math.sin(theta * 19)) * max(0, 1 - (z-.115)/.17)
            x = (rx + fold) * math.sin(theta)
            y = -(ry + fold) * math.cos(theta)
            # Slight forward slump, sculpted into the rest shape.
            y -= max(0, z - 1.3) * .10
            verts.append((x, y, z + hem))
            uv.append((j / sides, (z - .115) / 1.47))
            skin.append(skirt_weights(theta, z) if z < .99 else torso_weights(z))
        if i:
            for j in range(sides):
                faces.append(((i-1)*sides+j, (i-1)*sides+(j+1)%sides,
                              i*sides+(j+1)%sides, i*sides+j))
    body = mesh_object("Gown | continuous folded linen", verts, faces, linen, skin, uv)
    thickness(body)
    # Raised hem seam follows every fold, with exactly the same skinning.
    for row, label, radius in ((1, "Double-turned hem", .0028), (11, "Waist gather seam", .002)):
        points = [verts[row*sides+j] for j in range(sides)] + [verts[row*sides]]
        ws = [skin[row*sides+j] for j in range(sides)] + [skin[row*sides]]
        tube(label, points, [radius]*len(points), seam, ws, 5)
    # One discreet, raised front panel seam down each side.
    for j in (3, sides-3):
        points = [Vector(verts[i*sides+j]) + Vector((0, -.002, 0)) for i in range(14)]
        tube("Gown panel stitch", points, [.0017]*len(points), seam,
             [skin[i*sides+j] for i in range(14)], 5)


def make_sleeve(sign: int, linen: bpy.types.Material, lining: bpy.types.Material,
                seam: bpy.types.Material) -> None:
    suffix = "l" if sign > 0 else "r"
    shoulder = Vector((sign*.16, .055, 1.4555))
    wrist = Vector((sign*.697, .0654, 1.4555))
    axis = (wrist - shoulder).normalized()
    a = Vector((0, -1, 0))
    b = axis.cross(a).normalized()
    verts, faces, ws, uv = [], [], [], []
    sides, rings = 32, 15
    for i in range(rings):
        t = i/(rings-1)
        center = shoulder.lerp(wrist, t)
        radius = .070 + .051*min(1, t/.17) - .027*math.sin(math.pi*t) + .034*t*t
        # Drooping bell sleeve: more fullness below the forearm.
        for j in range(sides):
            th = TAU*j/sides
            fold = (.006 + .006*t)*math.sin(9*th+2*t) + .003*math.sin(17*th-6*t)
            p = center + a*(math.cos(th)*(radius+fold)) + b*(math.sin(th)*(radius+fold))
            p.z -= .052*t*t*(.5+.5*math.sin(th))
            verts.append(p)
            uv.append((j/sides, .32 + .62*(1-t)))
            if t < .26:
                ws.append(blend_weights("spine_03", f"upperarm_{suffix}", t/.26))
            else:
                ws.append(blend_weights(f"upperarm_{suffix}", f"lowerarm_{suffix}",
                                        max(0, min(1, (t-.35)/.34))))
        if i:
            for j in range(sides):
                faces.append(((i-1)*sides+j, (i-1)*sides+(j+1)%sides,
                              i*sides+(j+1)%sides, i*sides+j))
    obj = mesh_object(f"Bell sleeve.{suffix}", verts, faces, linen, ws, uv)
    obj.data.materials.append(lining)
    solid = obj.modifiers.new("Dark linen inside cuff", "SOLIDIFY")
    solid.thickness = .006
    solid.material_offset = 1
    solid.material_offset_rim = 0
    apply_modifier(obj, solid)
    for row in (rings-2,):
        points = [verts[row*sides+j] for j in range(sides)] + [verts[row*sides]]
        tube(f"Cuff stitching.{suffix}", points, [.0025]*len(points), seam,
             [ws[row*sides+j] for j in range(sides)] + [ws[row*sides]], 5)


def hood_point(theta: float, t: float) -> Vector:
    # Narrow crown leans slightly rearward; generous jaw and throat drape.
    z = 1.505 + .650*t
    rx = .192 * (1-t)**.75 + .003
    ry = .190 * (1-t)**.85 + .003
    if t < .25:
        rx += .028*(1-t/.25)
        ry += .035*(1-t/.25)
    fold = .0045*(1-t)*math.sin(10*theta + 2*t)
    x = (rx + fold)*math.sin(theta) + .025*t**3
    y = -(ry + fold)*math.cos(theta) + .002 + .045*t**2
    # Front cloth ridge suggests a nose beneath the hood; not a visible face.
    y -= .021*math.exp(-((theta+math.pi)%TAU-math.pi)**2/.035)*math.exp(-((t-.30)/.15)**2)
    return Vector((x, y, z))


def make_hood(linen: bpy.types.Material, lining: bpy.types.Material,
              seam: bpy.types.Material) -> None:
    sides, rings = 64, 33
    verts, faces, uv, ws = [], [], [], []
    for i in range(rings):
        t = i/(rings-1)
        for j in range(sides):
            theta = TAU*j/sides
            p = hood_point(theta, t)
            # Uneven hanging front bib.
            p.z -= .027 * (1-t)**12 * math.cos(theta*3)
            verts.append(p)
            uv.append((j/sides, .30+.69*t))
            ws.append(blend_weights("neck_01", "Head", min(1, t/.20)))
        if i:
            for j in range(sides):
                faces.append(((i-1)*sides+j, (i-1)*sides+(j+1)%sides,
                              i*sides+(j+1)%sides, i*sides+j))
    faces.append(tuple((rings-1)*sides+j for j in range(sides)))
    obj = mesh_object("Pointed hood | eye apertures", verts, faces, linen, ws, uv)
    thickness(obj, .006)
    # Actual cuts through the hood, backed by a recessed, unlit dark inner mask.
    for sign in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16,
                                           location=(sign*.037, -.154, 1.701))
        cutter = bpy.context.object
        cutter.scale = (.023, .095, .010)
        cutter.rotation_euler.y = sign*.13
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        mod = obj.modifiers.new("Cut sewn eye opening", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = cutter
        apply_modifier(obj, mod)
        bpy.data.objects.remove(cutter, do_unlink=True)
    # Boolean-created vertices inherit interpolation, then force full head influence
    # around the apertures to eliminate any version-specific weight interpolation.
    head_group = obj.vertex_groups.get("Head")
    for vertex in obj.data.vertices:
        if vertex.co.z > 1.68:
            for group in obj.vertex_groups:
                group.remove([vertex.index])
            head_group.add([vertex.index], 1, "REPLACE")
    # A recessed dark linen facing keeps eye openings shadowed without changing
    # or deleting any part of the original human face underneath.
    inner_verts, inner_faces = [], []
    for row in range(5):
        t = .255 + row*.025
        for col in range(13):
            theta = -.62 + col*.124/1.2
            p = hood_point(theta, t)
            p.y += .012
            inner_verts.append(p)
            if row and col:
                a = row*13+col
                inner_faces.append((a-14, a-13, a, a-1))
    mesh_object("Recessed eye lining", inner_verts, inner_faces, lining,
                [{"Head": 1}]*len(inner_verts))
    for theta in (math.pi, .64, TAU-.64):
        points = [hood_point(theta, i/48) for i in range(49)]
        tube("Hood flat-felled seam", points, [.0017]*49, seam,
             [blend_weights("neck_01", "Head", min(1, i/48/.2)) for i in range(49)], 5)
    # Cowl overlays the shoulder joints and gives the hood a sewn, layered base.
    verts, faces, ws, uv = [], [], [], []
    for i in range(9):
        t = i/8
        for j in range(64):
            th = TAU*j/64
            rx = .118 + .205*t
            ry = .098 + .096*t
            z = 1.58 - .125*t - .035*t*math.cos(th)**2 + .025*t*abs(math.sin(th))
            ripple = .006*math.sin(13*th)*(t**2)
            verts.append(((rx+ripple)*math.sin(th), -(ry+ripple)*math.cos(th)-.016, z))
            ws.append(blend_weights("neck_01", "spine_03", t))
            uv.append((j/64, .45+.4*(1-t)))
        if i:
            for j in range(64):
                faces.append((i*64+j, i*64+(j+1)%64, (i-1)*64+(j+1)%64, (i-1)*64+j))
    cowl = mesh_object("Shoulder cowl", verts, faces, linen, ws, uv)
    thickness(cowl, .006)
    edge = verts[-64:] + [verts[-64]]
    tube("Cowl stitched edge", edge, [.0028]*65, seam, ws[-64:]+[ws[-64]], 6)


def make_rope(rope: bpy.types.Material) -> None:
    count = 192
    for strand in range(3):
        points = []
        for i in range(count+1):
            theta = TAU*i/count
            twist = theta*42 + strand*TAU/3
            r = .006*math.cos(twist)
            points.append(((.194+r)*math.sin(theta), -(.149+r)*math.cos(theta),
                           1.073 + .005*math.sin(theta) + .006*math.sin(twist)))
        tube("Twisted rope girdle", points, [.0045]*len(points), rope,
             [{"pelvis": 1}]*len(points), 6)
    ellipsoid("Rope knot", (-.065, -.17, 1.073), (.024, .018, .019), rope, "pelvis")
    for strand in range(2):
        points = []
        for i in range(22):
            t = i/21
            points.append((-.065 + (.053 if strand else -.023)*t + .012*math.sin(t*7),
                           -.174-.055*t, 1.07-(.27 if strand else .35)*t))
        tube("Hanging belt end", points, [.007*(1-.3*i/21) for i in range(22)],
             rope, [{"pelvis": 1}]*22, 8)
        for j in range(4):
            end = Vector(points[-1])
            tube("Rope tassel", [end, end+Vector(((j-1.5)*.003, -.003, -.021))],
                 [.0018, .0007], rope, [{"pelvis": 1}]*2, 5)


def import_raider_base() -> bpy.types.Object:
    """Import the existing CC0 human unchanged; preserve its 65-bone rest rig."""
    bpy.ops.import_scene.gltf(
        filepath=str(ROOT / "content/characters/quaternius/Superhero_Male_FullBody.gltf"),
        bone_heuristic="BLENDER", disable_bone_shape=True,
    )
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    rig.name = "Armature"
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and any(mod.type == "ARMATURE" for mod in obj.modifiers):
            ASSETS.append(obj)
    for image in bpy.data.images:
        if image.has_data:
            image.pack()
    return rig


# The gown is a stiff bell weighted mostly to the pelvis, so a striding leg swings out through it,
# and a foot left below the hem would float ahead of it. The legs and feet it covers are removed
# from the body: faces whose vertices all lie below the hips in the rest pose. The cultist glides.
LEG_HIDE = (-1.0, .95)


def hide_covered_legs() -> int:
    body = max(BASE_MESHES, key=lambda obj: len(obj.data.vertices))
    bm = bmesh.new()
    bm.from_mesh(body.data)
    low, high = LEG_HIDE
    covered = [face for face in bm.faces
               if all(low <= (body.matrix_world @ vert.co).z <= high for vert in face.verts)]
    bmesh.ops.delete(bm, geom=covered, context="FACES")
    bm.to_mesh(body.data)
    bm.free()
    return len(covered)


def bind_garments() -> None:
    for obj in ASSETS:
        if any(mod.type == "ARMATURE" for mod in obj.modifiers):
            continue
        obj.parent = RIG
        modifier = obj.modifiers.new("Existing raider skeleton", "ARMATURE")
        modifier.object = RIG
    RIG.show_in_front = True
    RIG.data.display_type = "OCTAHEDRAL"


def set_rotation(name: str, xyz_degrees: tuple[float, float, float]) -> None:
    pb = RIG.pose.bones[name]
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = Euler(tuple(math.radians(v) for v in xyz_degrees)).to_quaternion()


def aim_bone(name: str, direction: tuple[float, float, float]) -> None:
    """Aim the bone's Y axis in armature space, accounting for its parent's pose."""
    bpy.context.view_layer.update()
    pb = RIG.pose.bones[name]
    parent_delta = (pb.parent.matrix.to_quaternion()
                    @ pb.parent.bone.matrix_local.to_quaternion().inverted())
    neutral = parent_delta @ pb.bone.matrix_local.to_quaternion()
    local_direction = neutral.inverted() @ Vector(direction).normalized()
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(local_direction)


def pose(kind: str, phase: float) -> None:
    for pb in RIG.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = (0, 0, 0)
    breath = math.sin(phase)
    set_rotation("spine_01", (3+breath*.7, 0, 0))
    set_rotation("spine_02", (2+breath*.7, 0, 0))
    set_rotation("Head", (-2, breath*1.2, -2))
    for sign in (1, -1):
        suffix = "l" if sign > 0 else "r"
        aim_bone(f"upperarm_{suffix}", (sign*.25, -.04, -.97))
        aim_bone(f"lowerarm_{suffix}", (sign*.16, -.16, -.97))
        for finger in ("index", "middle", "ring", "pinky", "thumb"):
            for i in range(1, 4):
                set_rotation(f"{finger}_{i:02d}_{suffix}", (7 if i == 1 else 13, 0, 0))
        if kind == "shamble":
            swing = math.sin(phase)*sign
            set_rotation(f"thigh_{suffix}", (swing*16, 0, 0))
            set_rotation(f"calf_{suffix}", (max(0, -swing)*-20, 0, 0))
            set_rotation(f"foot_{suffix}", (max(0, swing)*-8, 0, 0))
            aim_bone(f"upperarm_{suffix}", (sign*.29, -.18-swing*.18, -.94))
            aim_bone(f"lowerarm_{suffix}", (sign*.17, -.32-swing*.15, -.92))
        if kind == "reach":
            reach = (1-math.cos(phase))*.5
            aim_bone(f"upperarm_{suffix}", (sign*(.25+reach*.04), -.04-reach*.86, -.97+reach*.75))
            aim_bone(f"lowerarm_{suffix}", (sign*.16, -.16-reach*.83, -.97+reach*.92))
            set_rotation(f"hand_{suffix}", (reach*14, 0, 0))


def make_animations() -> None:
    for name, kind, frames in (("cultist_idle", "idle", 97),
                               ("cultist_shamble_preview", "shamble", 49),
                               ("cultist_reach_preview", "reach", 73)):
        RIG.animation_data_create()
        RIG.animation_data.action = bpy.data.actions.new(name)
        action = RIG.animation_data.action
        for frame in range(1, frames+1, (frames-1)//12):
            pose(kind, (frame-1)/(frames-1)*TAU)
            for pb in RIG.pose.bones:
                pb.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=pb.name)
        track = RIG.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, action)
        track.mute = True
        RIG.animation_data.action = None
    pose("idle", 0)


def verify_rig() -> dict:
    vertices = triangles = 0
    for obj in ASSETS:
        obj.data.calc_loop_triangles()
        vertices += len(obj.data.vertices)
        triangles += len(obj.data.loop_triangles)
        for vertex in obj.data.vertices:
            values = [g.weight for g in vertex.groups if g.weight > .00001]
            assert values, f"Unweighted vertex: {obj.name}:{vertex.index}"
            assert len(values) <= 4, f"More than four influences: {obj.name}:{vertex.index}"
            assert abs(sum(values)-1) < .002, (obj.name, vertex.index, sum(values))
            assert all(math.isfinite(c) for c in vertex.co)
    return {"mesh_objects_source": len(ASSETS), "vertices_blender": vertices,
            "triangles": triangles, "bones": len(RIG.data.bones),
            "maximum_skin_influences": 4, "units": "metres",
            "height_rest_m": round(max((obj.matrix_world @ vertex.co).z
                                      for obj in ASSETS for vertex in obj.data.vertices), 4),
            "blender_version": bpy.app.version_string,
            "base_model": "content/characters/quaternius/Superhero_Male_FullBody.gltf",
            "runtime_animation_library": "content/animations/quaternius/male.res",
            "blender_inspection_clips": ["cultist_idle", "cultist_shamble_preview", "cultist_reach_preview"]}


def aim(obj: bpy.types.Object, target: tuple) -> None:
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_studio() -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1100, 1400
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (.13, .13, .13)
    scene.view_settings.view_transform = "AgX"
    floor_mat = material("Studio charcoal (not exported)", (.025, .031, .038), .9)
    bpy.ops.mesh.primitive_plane_add(size=200)
    floor = bpy.context.object
    floor.name = "STUDIO | ground"
    floor.location.z = -.005
    floor.data.materials.append(floor_mat)
    for name, position, energy, size, color in (
        ("Key", (3, -4, 5), 500, 4, (1, .87, .69)),
        ("Fill", (-3, -1, 2.5), 240, 3, (.70, .82, 1)),
        ("Rim", (1, 3, 4), 650, 3, (1, .90, .78)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
        obj = bpy.data.objects.new("STUDIO | "+name, data)
        scene.collection.objects.link(obj)
        obj.location = position
        aim(obj, (0, 0, 1.1))
    data = bpy.data.cameras.new("Presentation camera")
    camera = bpy.data.objects.new("STUDIO | camera", data)
    scene.collection.objects.link(camera)
    data.type, data.ortho_scale, data.lens = "ORTHO", 2.85, 65
    camera.location = (3.0, -6, 2.7)
    aim(camera, (0, 0, 1.14))
    scene.camera = camera
    # Save into a clean material viewport focused on the rig, not on the studio.
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    RIG.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_distance = 3.5
                area.spaces.active.region_3d.view_location = (0, 0, 1.1)
                area.spaces.active.shading.type = "MATERIAL"
                area.spaces.active.clip_end = 100


def render_previews(samples: int) -> None:
    scene = bpy.context.scene
    scene.cycles.samples = samples
    for name, position, kind, phase in (
        ("cultist_beauty", (3, -6, 2.7), "idle", 0),
        ("cultist_front", (0, -6, 2.1), "idle", 0),
        ("cultist_back", (-3, 6, 2.6), "idle", 0),
        ("cultist_reach", (3, -6, 2.7), "reach", math.pi),
        ("cultist_stride", (3, -6, 2.7), "shamble", math.pi*.5),
    ):
        pose(kind, phase)
        scene.camera.location = position
        aim(scene.camera, (0, 0, 1.14))
        scene.render.filepath = str(OUT / "previews" / (name+".png"))
        bpy.ops.render.render(write_still=True)
    pose("idle", 0)


def main() -> None:
    global RIG
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-render", action="store_true")
    parser.add_argument("--render-only", action="store_true")
    parser.add_argument("--samples", type=int, default=48)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    for folder in ("source", "previews"):
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    if args.render_only:
        bpy.ops.wm.open_mainfile(filepath=str(OUT / "source/hooded_cultist.blend"))
        RIG = bpy.data.objects["Armature"]
        render_previews(args.samples)
        return
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    RIG = import_raider_base()
    BASE_MESHES.extend(ASSETS)
    print("CULTIST_LEGS_HIDDEN:", hide_covered_legs(), "faces")
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.render.fps = 24
    linen = fabric_material()
    lining = material("Unlit darkness inside hood", (.006, .004, .003), 1)
    seam = material("Linen seam thread", (.32, .255, .16), .94)
    rope = material("Twisted hemp", (.19, .125, .063), .98)
    make_body(linen, seam)
    for sign in (1, -1):
        make_sleeve(sign, linen, lining, seam)
    make_hood(linen, lining, seam)
    make_rope(rope)
    for obj in ASSETS:
        if obj in BASE_MESHES:
            continue
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=[face for face in bm.faces if len(face.verts) > 4])
        bm.to_mesh(obj.data)
        bm.free()
    bind_garments()
    stats = verify_rig()
    make_animations()
    # Export bind/rest pose; all animation actions are baked to portable glTF tracks.
    for pb in RIG.pose.bones:
        pb.rotation_quaternion = Quaternion()
    bpy.ops.object.select_all(action="DESELECT")
    # Preserve separate editable pieces in .blend, consolidate export draw surfaces.
    export_pieces = []
    for obj in ASSETS:
        if obj in BASE_MESHES:
            continue
        clone = obj.copy()
        clone.data = obj.data.copy()
        bpy.context.collection.objects.link(clone)
        clone.select_set(True)
        export_pieces.append(clone)
    bpy.context.view_layer.objects.active = export_pieces[0]
    bpy.ops.object.join()
    export_mesh = bpy.context.object
    export_mesh.name = "Cultist_Garments"
    for obj in BASE_MESHES:
        obj.select_set(True)
    RIG.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / "hooded_cultist.glb"), export_format="GLB",
        use_selection=True, export_animations=False,
        export_skins=True, export_def_bones=True, export_all_influences=False,
        export_yup=True, export_texcoords=True, export_normals=True,
        export_tangents=True, export_materials="EXPORT", export_cameras=False,
        export_lights=False, export_apply=False,
    )
    bpy.data.objects.remove(export_mesh, do_unlink=True)
    setup_studio()
    pose("idle", 0)
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, 97
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "source/hooded_cultist.blend"))
    (OUT / "model_stats.json").write_text(json.dumps(stats, indent=2)+"\n")
    print("CULTIST_RIG_OK:", json.dumps(stats))
    if not args.no_render:
        render_previews(args.samples)


if __name__ == "__main__":
    main()
