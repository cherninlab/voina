"""Vaulted passages built stone by stone, in Blender world space (z up).

A passage has one interface cross-section: a masonry.Opening centred on x = 0,
with its clear width, springing and rise. Long interiors can widen/lower while
the interfaces remain unchanged. It is built from three kinds of piece:

    groups = passage.run(lib, rng, o, a, b, 'P1', ext=(0.4, 0.0), planes=[(point, normal)])
    groups = passage.bay(lib, rng, quoins, o, centre, axis, {0: o, 3: o}, 'B1')   # an L bend
    groups = passage.portal(lib, rng, quoins, o, mouth, outward, 'M1')

- run: a straight stretch, level or sloped, between two centre-line floor
  points. Side walls have horizontal courses cut to the floor and springing
  lines. The barrel vault is made of staggered voussoir rings sheared to the
  slope, and a mortar mass surrounds it with the profile as its hole.
  `planes` trim the run to whatever it meets; `normal` points to the part
  that is cut away.
- bay: a square bay where runs meet (a bend, a T or a crossing). Runs arrive
  through its sides and a groin vault covers it: the two barrel vaults meet
  on the diagonals. A side without a run is a wall with a lunette under the
  vault; a narrower run gets its own arch in that wall.
- portal: a face wall with the passage's arch, where a run opens onto the
  shaft (a bridge or ledge starts there).

Every piece returns {group: [objects]}. Stones carry 'tone' and 'frame'; mortar
carries tone -1. The bake merges groups and takes collision from the mortar.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

from . import core, masonry, shapes

UP = Vector((0.0, 0.0, 1.0))
PAVING = None  # a floor-flag library for passage floors, if the caller has one
THICKNESS = 0.9
RING = 0.4
RECESS = 0.034


def _bake_transform(obj) -> None:
    obj.data = obj.data.copy()
    mirrored = obj.matrix_world.to_3x3().determinant() < 0
    obj.data.transform(obj.matrix_world)
    if mirrored:
        bm = bmesh.new(); bm.from_mesh(obj.data)
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data); bm.free()
    obj.matrix_world = Matrix.Identity(4)


def _shear(obj, origin: Vector, d: Vector, slope: float) -> None:
    """Lift every vertex by slope x its distance along d from origin."""
    _bake_transform(obj)
    for v in obj.data.vertices:
        v.co.z += slope * (v.co - origin).dot(d)


def clip_groups(groups: dict, planes) -> None:
    for key in groups:
        kept = []
        for obj in groups[key]:
            clip = clip_mass if obj.get('tone', 1.0) < 0 or obj.data.name.startswith('tunnel_rock') else masonry.clip
            if all(clip(obj, point, normal) for point, normal in planes):
                kept.append(obj)
            else:
                core.discard(obj)
        groups[key] = kept


def clip_mass(obj, point: Vector, normal: Vector) -> bool:
    """Cap the material around an opening, keeping the opening itself empty."""
    _bake_transform(obj)
    sides = [(v.co - point).dot(normal) for v in obj.data.vertices]
    if not sides or min(sides) >= 0:
        return False
    if max(sides) <= 0:
        return True
    bm = bmesh.new(); bm.from_mesh(obj.data)
    result = bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                                   plane_co=point, plane_no=normal, clear_outer=True)
    edges = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
    if edges:
        # edgeloop_fill fills the inner arch too, making a solid wall across
        # the passage. triangle_fill tessellates the outer loop with its hole.
        bmesh.ops.triangle_fill(bm, edges=edges, use_beauty=True)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data); bm.free()
    return bool(obj.data.polygons)


def box(name: str, centre: Vector, x: Vector, half: float, bottom: float, top: float):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(mesh)
    bm.free()
    y = UP.cross(x)
    obj = core.link(bpy.data.objects.new(name, mesh))
    obj.matrix_world = Matrix((x, y, UP)).transposed().to_4x4() @ Matrix.Diagonal((half * 2, half * 2, top - bottom, 1))
    obj.matrix_world.translation = centre + UP * ((bottom + top) * 0.5)
    _bake_transform(obj)
    obj['clip_box'] = [*centre, *x, half, bottom, top]
    return obj


def close_stone_back(obj) -> None:
    """Boolean cutters require closed stones, including hidden library backs."""
    shell = bmesh.new(); shell.from_mesh(obj.data)
    if all(edge.is_manifold for edge in shell.edges):
        shell.free()
        return
    bmesh.ops.remove_doubles(shell, verts=list(shell.verts), dist=0.000001)
    bmesh.ops.delete(shell, geom=[e for e in shell.edges if e.is_wire], context='EDGES')
    shared = [edge for edge in shell.edges if len(edge.link_faces) > 2]
    if shared:
        bmesh.ops.split_edges(shell, edges=shared)
    for vertex in list(shell.verts):
        edges = [edge for edge in vertex.link_edges if edge.is_boundary]
        if len(edges) > 2:
            bmesh.utils.vert_separate(vertex, edges)
    # Separate stones can touch at a clipped vertex. Trace each
    # face-connected component's back, rather than jumping to its
    # neighbour at that shared point.
    components = {}
    for seed in shell.faces:
        if seed in components:
            continue
        number = len(components)
        todo = [seed]
        while todo:
            face = todo.pop()
            if face in components:
                continue
            components[face] = number
            todo.extend(other for edge in face.edges for other in edge.link_faces if other not in components)
    boundary = {edge for edge in shell.edges if edge.is_boundary}
    caps = []
    # Jagged backs are nonplanar. A generic ngon fill can reuse
    # visible stone diagonals and create nonmanifold edges. Give
    # each closed boundary its own hidden centre and triangle fan.
    while boundary:
        edge = next(iter(boundary))
        component = components[edge.link_faces[0]]
        start = current = edge.verts[0]
        loop = []
        while True:
            loop.append(current)
            boundary.remove(edge)
            current = edge.other_vert(current)
            if current == start:
                break
            choices = [candidate for candidate in current.link_edges if candidate in boundary and
                       components[candidate.link_faces[0]] == component]
            assert len(choices) == 1, (obj.name, "Branched open back")
            edge = choices[0]
        centre = shell.verts.new(sum((vertex.co for vertex in loop), Vector()) / len(loop))
        for index, vertex in enumerate(loop):
            caps.append(shell.faces.new((vertex, loop[(index + 1) % len(loop)], centre)))
    for layer in list(shell.loops.layers.float_color.values()) + list(shell.loops.layers.color.values()):
        for face in caps:
            for loop in face.loops:
                loop[layer] = (0.65, 0.65, 0.65, 1)
    bmesh.ops.triangulate(shell, faces=list(shell.faces))
    bmesh.ops.recalc_face_normals(shell, faces=list(shell.faces))
    assert all(edge.is_manifold for edge in shell.edges), (obj.name, {n:sum(len(e.link_faces)==n for e in shell.edges) for n in (0,1,2,3,4)})
    shell.to_mesh(obj.data); shell.free()
    obj.data.update(); obj.data.calc_loop_triangles()
    obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
    for face in obj.data.polygons:
        face.use_smooth = False


def difference(obj, cutter, pending: list) -> None:
    """Cut the same clear volume out of visible stones and collision backing."""
    _bake_transform(obj)
    # Most stones don't touch this opening. Avoid thousands of empty booleans.
    corners = [cutter.matrix_world @ Vector(v) for v in cutter.bound_box]
    if any(max(v.co[k] for v in obj.data.vertices) < min(v[k] for v in corners) - 0.001 or
           min(v.co[k] for v in obj.data.vertices) > max(v[k] for v in corners) + 0.001 for k in range(3)):
        return
    if 'clip_box' in cutter or 'arch_clear' in cutter:
        values = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
        obj.data.vertices.foreach_get('co', values)
        points = values.reshape(-1, 3)
        if 'clip_box' in cutter:
            c = list(cutter['clip_box'])
            relative = points - np.array(c[:3])
            x = np.array(c[3:6]); y = np.cross([0, 0, 1], x)
            inside = ((np.abs(relative @ x) <= c[6]) & (np.abs(relative @ y) <= c[6]) &
                      (relative[:, 2] >= c[7]) & (relative[:, 2] <= c[8]))
        else:
            c = list(cutter['arch_clear'])
            relative = points - np.array(c[:3])
            d = np.array(c[3:6]); side = np.cross(d, [0, 0, 1])
            u, s = relative @ side, relative @ d
            z = relative[:, 2] - s * c[12]
            inside = ((s >= c[6]) & (s <= c[7]) & (np.abs(u) <= c[8]) & (z >= -1.0) &
                      ((z <= c[9]) | (u * u + (z - c[10]) ** 2 <= c[11] ** 2)))
        if inside.all():
            obj.data.clear_geometry()
            return
    modifier = obj.modifiers.new('shared_clearance', 'BOOLEAN')
    modifier.operation = 'DIFFERENCE'
    modifier.solver = 'EXACT'
    modifier.use_hole_tolerant = True
    modifier.object = cutter
    pending.append(obj)


def subtract(groups: dict, cutters) -> None:
    for cutter in cutters:
        pending = []
        for objects in groups.values():
            for obj in objects:
                if obj.data.vertices:
                    difference(obj, cutter, pending)
        if pending:
            # Build/evaluate one dependency graph per cut, not per stone.
            depsgraph = bpy.context.evaluated_depsgraph_get()
            meshes = [bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph)) for obj in pending]
            for obj, mesh in zip(pending, meshes):
                obj.modifiers.clear()
                obj.data = mesh
    for key, objects in groups.items():
        kept = []
        for obj in objects:
            if obj.data.polygons:
                kept.append(obj)
            else:
                core.discard(obj)
        groups[key] = kept


def clearance(o: masonry.Opening, centre: Vector, d: Vector, start: float, end: float, name: str, slope: float = 0.0, padding: float = 0.0):
    """Closed arch prism, on the actual arrival axis (never its cardinal side)."""
    if padding:
        o = masonry.Opening(-o.half-padding, o.half+padding, spring=o.spring, rise=o.crown-o.spring+padding)
    side = d.cross(UP)
    profile = [(-o.half, -1.0), (o.half, -1.0)]
    for k in range(49):
        angle = o.a0 + (math.pi - 2 * o.a0) * k / 48
        profile.append((o.radius * math.cos(angle), o.cy + o.radius * math.sin(angle)))
    vertices = [centre + d * s + side * u + UP * (z + slope * s) for s in (start, end) for u, z in profile]
    count = len(profile)
    faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    faces += [(k, (k + 1) % count, (k + 1) % count + count, k + count) for k in range(count)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = core.link(bpy.data.objects.new(name, mesh))
    obj['arch_clear'] = [*centre, *d, start, end, o.half, o.spring, o.cy, o.radius, slope]
    return obj


def skew_bay(lib, rng, o: masonry.Opening, centre: Vector, axis: Vector, arrivals: list, name: str) -> dict:
    """A groin junction is the union of its real barrels, including skew ones.

    Cardinal holes leave wedges when an oblique run meets a square bay. Use
    the same arch prisms for roof, walls and backing; clip runs to the entire
    bay footprint so they also cover an arrival that crosses a corner.
    """
    h = o.half
    hewn = all(a['route']['id'] in ('root_tunnel','cave_bypass') for a in arrivals)
    y = UP.cross(axis)
    planes = [(centre + d * h, d) for d in (axis, y, -axis, -y)]
    reach = 3 * (h + THICKNESS)
    full = [clearance(a['profile'], centre, a['away'], -reach, reach, f'{name}_web{k}', a.get('slope', 0.0))
            for k, a in enumerate(arrivals)]
    if hewn:
        full=[clearance(o,centre,axis,-reach,reach,f'{name}_hewn_chamber')]
    doors = [clearance(a['profile'], centre, a['away'], 0, reach, f'{name}_mouth{k}', a.get('slope', 0.0))
             for k, a in enumerate(arrivals)]
    def crop(cutters, recess=0.0):
        chamber = []
        for cutter in cutters:
            inside = core.link(cutter.copy()); inside.data = cutter.data.copy()
            cropped = {0: [inside]}; clip_groups(cropped, [(p+n*recess,n) for p,n in planes])
            del inside['arch_clear']
            bm = bmesh.new(); bm.from_mesh(inside.data)
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            bm.to_mesh(inside.data); bm.free()
            chamber.append(inside)
        return chamber

    chamber = crop(full)
    outer = [clearance(a['profile'],centre,a['away'],-reach,reach,f'{name}_outer{k}',a.get('slope',0.0),RING)
             for k,a in enumerate(arrivals)]
    groups = {}
    for k, d in ([] if hewn else enumerate((axis, y, -axis, -y))):
        along = d.cross(UP)
        wall = masonry.Wall(2 * (h + THICKNESS), o.crown + .3, THICKNESS)
        parts = wall.build(lib, rng, name=f'{name}_wall{k}', core=False)
        masonry.place(parts, centre + d * h - along * (h + THICKNESS), along, UP)
        groups[k] = parts
    # Incoming linings own their thickness too: leaving bay-facing chips
    # inside that shell makes them protrude through the rock or run wall.
    wall_doors = [clearance(a['profile'],centre,a['away'],0,reach,f'{name}_wall_mouth{k}',a.get('slope',0.0),
                            .6 if a['route']['id'] in ('root_tunnel','cave_bypass') else RING)
                  for k,a in enumerate(arrivals)]
    subtract(groups, wall_doors + chamber)
    for k, arrival in enumerate([] if hewn else arrivals):
        d = arrival['away']
        slope = arrival.get('slope', 0.0)
        roof = {0: _vault(rng, arrival['profile'], centre - d * reach - UP * slope * reach, d,
                         2 * reach, f'{name}_branch{k}', slope=slope)}
        clip_groups(roof, planes)
        # Earlier barrels own their stone thickness; later webs cannot overlap it.
        subtract(roof, outer[:k] + full[k+1:])
        groups[4 + k] = roof[0]
    roof_top = o.crown + RING + .3 + max(abs(a.get('slope', 0.0)) for a in arrivals) * (h + THICKNESS) * 2
    mass = box(f'{name}_mass', centre, axis, h + THICKNESS, -0.15, roof_top)
    mass['tone'] = -1.0
    backing = {0: [mass]}
    recessed_full = [clearance(a['profile'],centre,a['away'],-reach,reach,f'{name}_recess{k}',a.get('slope',0.0),RECESS)
                     for k,a in enumerate(arrivals)]
    recessed_doors = [clearance(a['profile'],centre,a['away'],0,reach,f'{name}_recess_door{k}',a.get('slope',0.0),RECESS)
                      for k,a in enumerate(arrivals)]
    if hewn:
        for cutter in recessed_full:core.discard(cutter)
        recessed_full=[clearance(o,centre,axis,-reach,reach,f'{name}_hewn_recess',padding=RECESS)]
    recessed_chamber = crop(recessed_full, RECESS)
    subtract(backing, recessed_chamber + recessed_doors)
    groups[20] = backing[0]
    if hewn:
        # A cut-rock route keeps cut-rock junctions. Independent brick skins
        # at every bend made arbitrary grey patches in the hewn corridor.
        skin=box('tunnel_rock_'+name,centre,axis,h+THICKNESS,-.15,roof_top)
        inner_full=[clearance(a['profile'],centre,a['away'],-reach,reach,f'{name}_rock_inner{k}',a.get('slope',0.0),-.04)
                    for k,a in enumerate(arrivals)]
        inner_doors=[clearance(a['profile'],centre,a['away'],0,reach,f'{name}_rock_door{k}',a.get('slope',0.0),-.04)
                     for k,a in enumerate(arrivals)]
        for cutter in inner_full:core.discard(cutter)
        inner_full=[clearance(o,centre,axis,-reach,reach,f'{name}_hewn_inner',padding=-.04)]
        inner_chamber=crop(inner_full)
        exterior=[]
        for cutter in wall_doors:
            outside=core.link(cutter.copy());outside.data=cutter.data.copy()
            if 'arch_clear' in outside:del outside['arch_clear']
            hole=box('rock_interface_domain',centre,axis,h,-20,30)
            parts={0:[outside]};subtract(parts,[hole]);core.discard(hole)
            exterior+=parts[0]
        rocks={0:[skin]};subtract(rocks,inner_chamber+inner_doors+exterior)
        for obj in rocks[0]:
            # Run and bay Boolean caps otherwise occupy the same plane.
            # Bury the bay's outer cap inside the incoming lining.
            for vertex in obj.data.vertices:
                for normal in (axis,y,-axis,-y):
                    if abs((vertex.co-centre).dot(normal)-h)<.001:
                        vertex.co+=normal*.012
            obj.data.update()
            obj.data.name='tunnel_rock_'+name
            obj['tone']=.8;obj['frame']=[1,0,0,0,0,1,0,-1,0]
        groups[0]=rocks[0]
        for cutter in inner_full+inner_doors+inner_chamber+exterior:core.discard(cutter)
    groups[21] = pave_field(lib,centre-axis*h,axis,2*h,h,f'{name}_floor')
    for cutter in full + doors + wall_doors + chamber + outer + recessed_full + recessed_doors + recessed_chamber:
        core.discard(cutter)
    if hewn:
        for obj in groups[0]+groups[20]:carve_rock(obj,centre.z)
    return groups


def _mass(o: masonry.Opening, length: float, name: str, top: float = None) -> bpy.types.Object:
    """Mortar block around the profile, wall-local: x across (0 .. width),
    y up, extruded along -z for `length`; the hole is the profile grown by
    the recess so the stones' faces show."""
    width = o.half * 2.0 + 2.0 * THICKNESS
    # The smooth game ribbon owns walking floors. A core floor plate across
    # an extended flat run would form a ledge over the adjoining ramp.
    hole = masonry.Opening(THICKNESS - RECESS, THICKNESS + o.half * 2.0 + RECESS, -0.2, o.spring, o.crown - o.spring + RECESS)
    wall = masonry.Wall(width, top or o.crown + RING + 0.3, length + RECESS, [hole], recess=RECESS)
    return wall.core(name)


RING_WIDTH = 0.42
_RINGS = {}


def _ring_variants(rng, o: masonry.Opening, stagger: bool, triangles: int, count: int = 3) -> list:
    """A few sculpted rings per profile, reused down a vault: every ring of a
    long tunnel sculpted anew would take hours, and real vault stones are cut
    to a handful of templates anyway. Each variant is [(mesh)] in voussoir
    axes (arch in x-z about the intrados centre, RING_WIDTH thick on y)."""
    key = (round(o.radius, 3), round(o.a0, 4), stagger, triangles)
    if key not in _RINGS:
        variants = []
        # Sculpt templates outside the growing dungeon scene: Blender operators
        # otherwise rebuild a dependency graph containing every earlier stone.
        scene = bpy.data.scenes.new('PassageTemplates')
        with bpy.context.temp_override(scene=scene, view_layer=scene.view_layers[0]):
            for number in range(count):
                meshes = []
                for piece in masonry.ring(rng, o, RING, RING_WIDTH, f'vault_template_{len(_RINGS)}_{number}', stagger=stagger,
                                          triangles=triangles):
                    piece.data.transform(piece.matrix_world)
                    meshes.append(piece.data)
                    core.discard(piece)
                variants.append(meshes)
        bpy.data.scenes.remove(scene)
        _RINGS[key] = variants
    return _RINGS[key]


def _vault(rng, o: masonry.Opening, start: Vector, d: Vector, length: float, name: str, slope: float = 0.0,
           triangles: int = 140) -> list:
    """Barrel vault rings along d from `start` (centre-line floor point)."""
    side = d.cross(UP)
    frame = Matrix((side, d, UP)).transposed().to_4x4()
    result = []
    s, number = 0.0, 0
    while length - s > 1e-6:
        width = rng.uniform(0.34, 0.48)
        if length - (s + width) < 0.25:
            width = length - s
        joint = rng.uniform(0.008, 0.02)
        centre = start + d * (s + width * 0.5) + UP * (o.cy + slope * (s + width * 0.5))
        variant = rng.choice(_ring_variants(rng, o, number % 2 == 1, triangles))
        mirror = -1.0 if rng.random() < 0.5 else 1.0
        scale = Matrix.Diagonal((mirror, (width - joint) / RING_WIDTH, 1.0, 1.0))
        for k, mesh in enumerate(variant):
            piece = core.link(bpy.data.objects.new(f'{name}_ring{number}_{k}', mesh))
            piece.matrix_world = Matrix.Translation(centre) @ frame @ scale
            if slope:
                _shear(piece, centre, d, slope)
            piece['tone'] = rng.uniform(0.8, 1.15)
            piece['frame'] = [*d, *UP, *side]
            result.append(piece)
        s += width
        number += 1
    return result


def pave(lib, rng, start: Vector, d: Vector, length: float, half: float, slope: float, name: str) -> list:
    """Stone floor along d from `start` (centre-line floor point), wall to
    wall: flags laid in rows on the level, treads stepping up a ramp. The
    walking collision stays the game's smooth ribbon; the stones sit on it."""
    side = d.cross(UP)
    frame_rot = Matrix((side, d, UP)).transposed().to_4x4()
    result, s = [], 0.0
    stepped = abs(slope) > 0.06
    while length - s > 0.05:
        depth = min(0.34 if stepped else rng.uniform(0.45, 0.85), length - s)
        top = start.z + slope * ((s + depth) if slope > 0 else s) + 0.015
        x = -half
        while half - x > 0.05:
            width = rng.uniform(0.6, 1.3)
            if half - (x + width) < 0.35:
                width = half - x
            joint = rng.uniform(0.006, 0.014)
            stone = (PAVING or lib).place(rng, width - joint, depth - joint, 0.14, f'{name}_flag')
            frame = frame_rot.copy()
            frame.translation = Vector((start.x, start.y, top)) + d * (s + depth * 0.5) + side * (x + width * 0.5)
            stone.matrix_world = frame @ stone.matrix_world
            stone['frame'] = [*side, *d, *UP]
            result.append(stone)
            x += width
        s += depth
    return result


def rock_shell(o: masonry.Opening, start: Vector, d: Vector, length: float, slope: float, name: str):
    """A continuous hewn face, with broad facets rather than masonry courses."""
    side = d.cross(UP)
    section = [(-o.half, -0.12), (-o.half, o.spring)]
    section += [(o.radius * math.cos(math.pi - o.a0 - (math.pi - 2 * o.a0) * i / 24),
                 o.cy + o.radius * math.sin(math.pi - o.a0 - (math.pi - 2 * o.a0) * i / 24)) for i in range(1, 25)]
    section += [(o.half, -0.12)]
    count, steps = len(section), max(2, math.ceil(length / 0.55))
    vertices = []
    for layer in range(2):
        for j in range(steps + 1):
            s = length * j / steps
            fade = min(1.0, s, length - s)
            for i, (u, z) in enumerate(section):
                outward = Vector((u, 0, max(0, z - o.spring))).normalized()
                noise = fade * (0.045 + 0.045 * math.sin(s * 1.9 + i * 1.71) * math.sin(s * .63 - i * .8))
                offset = (0.55 if layer else -noise)
                vertices.append(start + d * s + side * (u + outward.x * offset) + UP * (z + slope * s + outward.z * offset))
    n = (steps + 1) * count
    faces = []
    for j in range(steps):
        for i in range(count - 1):
            a = j * count + i
            faces += [(a, a + count, a + count + 1), (a, a + count + 1, a + 1),
                      (a + n, a + n + 1, a + n + count + 1), (a + n, a + n + count + 1, a + n + count)]
    for j in range(steps):
        for i in (0, count - 1):
            a = j * count + i
            faces.append((a, a + n, a + n + count, a + count))
    for j in (0, steps):
        for i in range(count - 1):
            a = j * count + i
            faces.append((a, a + 1, a + n + 1, a + n))
    mesh = bpy.data.meshes.new('tunnel_rock_' + name)
    mesh.from_pydata(vertices, [], faces)
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    mesh.shade_smooth()
    mesh.set_sharp_from_angle(angle=math.radians(38))
    obj = core.link(bpy.data.objects.new('tunnel_rock_' + name, mesh))
    obj['tone'] = .8
    obj['frame'] = [*d, *UP, *side]
    return obj


def pave_field(lib, start: Vector, d: Vector, length: float, half: float, name: str) -> list:
    """One world-aligned stone field; clipped halves keep the same stone/UVs."""
    library=PAVING or lib
    side=d.cross(UP)
    end=start+d*length
    corners=[p+side*sign*half for p in (start,end) for sign in (-1,1)]
    low=Vector((min(p.x for p in corners),min(p.y for p in corners),start.z))
    high=Vector((max(p.x for p in corners),max(p.y for p in corners),start.z))
    planes=[(start,-d),(end,d),(start+side*half,side),(start-side*half,-side)]
    result=[]
    for row in range(math.floor(low.y/.7)-1,math.ceil(high.y/.7)+1):
        for column in range(math.floor(low.x/.9)-1,math.ceil(high.x/.9)+1):
            x=(column+.5+(row%2)*.5)*.9;y=(row+.5)*.7
            rng=core.rng(177,'paving-field',column,row)
            used=library.used;library.used={}
            obj=library.place(rng,.888,.688,.14,f'{name}_cell_{column}_{row}')
            library.used=used
            obj.matrix_world=Matrix.Translation((x,y,start.z+.015))@obj.matrix_world
            obj['frame']=[1,0,0,0,1,0,0,0,1]
            obj['paving_cell']=[column,row];obj['mapping_origin']=[x,y,0]
            obj['tone']=rng.uniform(.88,1.04)
            _bake_transform(obj)
            pieces={0:[obj]};clip_groups(pieces,planes)
            result+=pieces[0]
    return result


def shape_run(groups: dict, o: masonry.Opening, a: Vector, b: Vector, style: str) -> None:
    """Widen/lower the middle; leave four metres at every join unchanged."""
    flat = Vector((b.x - a.x, b.y - a.y, 0))
    d, side = flat.normalized(), flat.normalized().cross(UP)
    slope = (b.z - a.z) / flat.length
    for group,objects in groups.items():
        if group == 4:
            continue
        for obj in objects:
            _bake_transform(obj)
            if obj.get('tone', 1.0) < 0 and flat.length > 8:
                bm = bmesh.new(); bm.from_mesh(obj.data)
                longitudinal = [edge for edge in bm.edges if abs((edge.verts[1].co-edge.verts[0].co).dot(d)) > flat.length*.8]
                if longitudinal:
                    bmesh.ops.subdivide_edges(bm, edges=longitudinal, cuts=max(1,math.ceil(flat.length/.5)-1), use_grid_fill=True)
                bm.to_mesh(obj.data); bm.free()
            for vertex in obj.data.vertices:
                relative = vertex.co - a
                s, u = relative.dot(d), relative.dot(side)
                t = max(0.0, min(1.0, (s - 4.0) / 3.0, (flat.length - s - 4.0) / 3.0))
                weight = t * t * (3 - 2 * t)
                height = relative.z - slope * s
                vertex.co += side * (u / o.half * .28 * weight)
                vertex.co.z -= .22 * weight * max(0.0, min(1.0, (height - o.spring) / max(.1, o.crown - o.spring)))
            obj.data.update()


def mine_shores(rng, o, start, d, length, slope, name) -> list:
    """Posts stand in wall pockets; paired braces carry a restrained bowed tie."""
    side = d.cross(UP)
    builder = shapes.Builder('tunnel_wood_' + name)
    for k in range(max(0, math.floor((length - 8.4) / 3.8)) + 1):
        s = 4.2 + k * 3.8
        if s > length - 4.2:
            break
        centre = start + d * s + UP * slope * s
        half, top = o.half + .02, o.spring + .18
        for sign in (-1, 1):
            foot = centre + side * half * sign - UP * .12
            head = centre + side * half * sign + UP * top
            shapes.timber(builder, foot, head, .22, .25, d, rng)
            shapes.timber(builder, head - UP * .60, head - side * sign * .56, .14, .16, d, rng)
        shapes.timber(builder, centre - side * (half + .14) + UP * top,
                      centre + side * (half + .14) + UP * top, .24, .28, UP, rng, bow=-.025)
    if not builder.pieces:
        builder.bm.free()
        return []
    obj = builder.to_object()
    obj['tone'] = .82
    return [obj]


def edge_spalls(rng, o, start, d, length, slope, name) -> list:
    """A small fallen patch against one wall, outside the walking ribbon."""
    if length < 6:
        return []
    side = d.cross(UP)
    sign = rng.choice((-1, 1))
    place = rng.uniform(2, length - 2)
    result = []
    for k in range(rng.randint(4, 7)):
        s = max(.5, min(length - .5, place + rng.uniform(-.8, .8)))
        radius = rng.uniform(.09, .20)
        mesh = bpy.data.meshes.new('tunnel_spall')
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1)
        bm.to_mesh(mesh); bm.free()
        obj = core.link(bpy.data.objects.new(f'{name}_fallen{k}', mesh))
        for v in obj.data.vertices:
            v.co *= rng.uniform(.75, 1.15)
        obj.matrix_world = Matrix.Diagonal((radius, radius * rng.uniform(.6, 1.4), radius * .6, 1))
        obj.matrix_world.translation = start + d * s + side * sign * (o.half + radius * .3) + UP * (slope * s + radius * .35)
        obj['tone'] = rng.uniform(.65, 1.0)
        obj['frame'] = [*d, *UP, *side]
        result.append(obj)
    return result


def run_mass(o, a: Vector, b: Vector, name: str, ext=(0.0,0.0)):
    flat = Vector((b.x-a.x,b.y-a.y,0))
    d = flat.normalized(); side = d.cross(UP)
    slope = (b.z-a.z)/flat.length
    start = a-d*ext[0]-UP*slope*ext[0]
    mass = _mass(o,flat.length+sum(ext),name)
    masonry.place([mass],start-d*RECESS-side*(o.half+THICKNESS),side,UP)
    if slope:
        _shear(mass,start,d,slope)
    return mass


def run(lib, rng, o: masonry.Opening, a: Vector, b: Vector, name: str, ext=(0.0, 0.0), planes=(),
        triangles: int = 140, style: str = 'masonry', vary: bool = True) -> dict:
    """A straight stretch from floor point a to floor point b (3D), extended
    by ext beyond each end and trimmed by planes."""
    flat = Vector((b.x - a.x, b.y - a.y, 0.0))
    d = flat.normalized()
    side = d.cross(UP)
    slope = (b.z - a.z) / flat.length
    s0, s1 = -ext[0], flat.length + ext[1]
    length = s1 - s0

    def at(s: float) -> Vector:
        return a + d * s + UP * slope * s

    start, end = at(s0), at(s1)
    low = min(start.z, end.z)
    climb = abs(end.z - start.z)
    height = o.spring + climb
    groups = {0: [], 1: [], 2: [], 3: [], 4: []}
    rows = masonry.Wall(1.0, height).courses(rng, {0.0, height} if climb > 0.05 else {0.0, o.spring})
    for number, (origin, along) in enumerate((((start.x, start.y), d), ((end.x, end.y), -d))):
        base = Vector((origin[0], origin[1], low)) + (-side if number == 0 else side) * o.half
        wall = masonry.Wall(length, height, THICKNESS)
        pieces = wall.build(lib, rng, name=f'{name}_side{number}', rows=rows, core=False)
        masonry.place(pieces, base, along, UP)
        groups[number] = pieces
    if climb > 0.05:
        # Horizontal courses, cut along the slope at the floor and the springing.
        floor_normal = (UP - d * slope).normalized()
        cuts = [(start, -floor_normal), (start + UP * o.spring, floor_normal)]
        sides = {0: groups[0], 1: groups[1]}
        clip_groups(sides, cuts)
        groups[0], groups[1] = sides[0], sides[1]
    groups[2] = _vault(rng, o, start, d, length, name, slope, triangles)
    groups[4] = pave_field(lib,start,d,length,o.half+(.28 if vary else 0.0),name)
    mass = run_mass(o,a,b,f'{name}_mass',ext)
    groups[3] = [mass]
    groups[6] = edge_spalls(rng, o, start, d, length, slope, name)
    if style in ('hewn_rock', 'timber_mine') and length > 4.0:
        # Room doorways and junctions own the masonry transitions; do not
        # leave a second arch collar protruding through the rock lining.
        for key in (0, 1, 2):
            for obj in groups[key]:
                core.discard(obj)
            groups[key] = []
        groups[0].append(rock_shell(o, start, d, length, slope, name))
        if style == 'timber_mine':
            groups[5] = mine_shores(rng, o, start, d, length, slope, name)
    if vary:
        shape_run(groups, o, a, b, style)
    clip_groups(groups, planes)
    return groups


def _keep_under_arc(obj, o: masonry.Opening, centre_x: float) -> bool:
    """Wall-local: trim a lunette wall stone to below the vault's intrados
    (centred at x = centre_x). False when nothing is left."""
    position = obj.matrix_world.translation
    u = position.x - centre_x
    if position.y <= o.spring:
        return True
    if abs(u) >= o.half:
        return False
    hub = Vector((centre_x, o.cy, 0.0))
    offset = Vector((u, position.y - o.cy, 0.0))
    direction = offset.normalized() if offset.length > 1e-6 else Vector((0.0, 1.0, 0.0))
    return masonry.clip(obj, hub + direction * (o.radius + 0.004), direction)


def bay(lib, rng, quoins, o: masonry.Opening, centre: Vector, axis: Vector, sides: dict, name: str) -> dict:
    """A square bay of half-size o.half on floor point `centre`. `axis` is
    the bay's horizontal x; `sides` maps 0 (+x), 1 (+y), 2 (-x), 3 (-y) to
    the profile of the run arriving there (absent: a solid wall)."""
    x = Vector((axis.x, axis.y, 0.0)).normalized()
    y = UP.cross(x)
    h = o.half
    directions = [x, y, -x, -y]
    groups = {}
    top = o.crown + RING + 0.3
    for k, outward in enumerate(directions):
        arriving = sides.get(k)
        if arriving is not None and abs(arriving.half - h) < 0.05:
            continue  # the run continues the bay's vault through this side
        along = outward.cross(UP)
        # Run on past the corners where the neighbouring side is walled too, so corners bond.
        start_side, end_side = ((k + 1) % 4, (k + 3) % 4) if along.dot(directions[(k + 1) % 4]) < 0 else ((k + 3) % 4, (k + 1) % 4)
        before = THICKNESS if sides.get(start_side) is None else 0.0
        after = THICKNESS if sides.get(end_side) is None else 0.0
        length = 2.0 * h + before + after
        openings = []
        if arriving is not None:
            openings.append(masonry.Opening(before + h - arriving.half, before + h + arriving.half, 0.0, arriving.spring,
                                            rise=arriving.crown - arriving.spring))
        wall = masonry.Wall(length, o.crown + 0.05, THICKNESS, openings)
        pieces = wall.build(lib, rng, quoins=quoins, name=f'{name}_wall{k}')
        kept = []
        for piece in pieces:
            if piece.get('tone', 1.0) < 0 or _keep_under_arc(piece, o, before + h):
                kept.append(piece)
            else:
                core.discard(piece)
        masonry.place(kept, centre + outward * h - along * (before + h), along, UP)
        groups[k] = kept
    # Groin vault: the vault along x keeps the triangles over the +-x sides,
    # the vault along y those over +-y; they meet on the diagonals.
    for number, (direction, other) in enumerate(((x, y), (y, x))):
        rings = _vault(rng, o, centre - direction * h, direction, 2.0 * h, f'{name}_vault{number}')
        kept = []
        for piece in rings:
            world = [piece.matrix_world @ v.co for v in piece.data.vertices]
            mean = sum(world, Vector()) / max(len(world), 1)
            sign = 1.0 if (mean - centre).dot(direction) >= 0 else -1.0
            planes = [(centre, (-direction * sign + other).normalized()), (centre, (-direction * sign - other).normalized())]
            if all(masonry.clip(piece, point, normal) for point, normal in planes):
                kept.append(piece)
            else:
                core.discard(piece)
        groups[4 + number] = kept
    groups[7] = pave_field(lib,centre-x*h,x,2*h,h,f'{name}_floor')
    # Mass: a block over the bay and its walls, holed by both vaults' profiles.
    # Block A: across y, extruded along x (local -z runs along -(y x up) = -x from its origin).
    mass = _mass(o, 2.0 * (h + THICKNESS) + 1.0, f'{name}_mass', top)
    masonry.place([mass], centre + x * (h + THICKNESS + 0.5 + RECESS) - y * (h + THICKNESS), y, UP)
    _bake_transform(mass)
    # Block B: across x, extruded along y.
    cutter = _mass(o, 2.0 * (h + THICKNESS) + 1.0, f'{name}_cut', top + 1.0)
    masonry.place([cutter], centre - x * (h + THICKNESS) - y * (h + THICKNESS + 0.5 + RECESS), x, UP)
    _bake_transform(cutter)
    # The second block's material is what both holes leave: intersect.
    boolean = mass.modifiers.new('groin', 'BOOLEAN')
    boolean.operation = 'INTERSECT'
    boolean.solver = 'EXACT'
    boolean.object = cutter
    depsgraph = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(mass.evaluated_get(depsgraph))
    mass.modifiers.clear()
    mass.data = baked
    core.discard(cutter)
    mass['tone'] = -1.0
    groups[6] = [mass]
    return groups


def rock_cut_offset(co: Vector, floor: float) -> Vector:
    """One world field keeps separately built rock/core interfaces together."""
    weight=max(0.0,min(1.0,(co.z-floor-.12)/.65))
    weight=weight*weight*(3-2*weight)
    broad=noise.noise_vector(co*.85,noise_basis='PERLIN_ORIGINAL')*.15
    chips=noise.noise_vector(co*3.7,noise_basis='PERLIN_ORIGINAL')*.035
    return (broad+chips)*weight


def carve_rock(obj, floor: float) -> None:
    """Give long cut faces real relief; the floor stays fixed and walkable."""
    _bake_transform(obj)
    shell=bmesh.new();shell.from_mesh(obj.data)
    bmesh.ops.triangulate(shell,faces=list(shell.faces))
    for _ in range(7):
        long=[edge for edge in shell.edges if edge.calc_length()>.55]
        if not long:break
        bmesh.ops.subdivide_edges(shell,edges=long,cuts=1,use_grid_fill=True)
    for vertex in shell.verts:vertex.co+=rock_cut_offset(vertex.co,floor)
    bmesh.ops.recalc_face_normals(shell,faces=list(shell.faces))
    shell.to_mesh(obj.data);shell.free();obj.data.update()
    obj.data.shade_smooth();obj.data.set_sharp_from_angle(angle=math.radians(38))


def turning_portal(lib, rng, o: masonry.Opening, exit_profile: masonry.Opening,
                   mouth: Vector, incoming: Vector, outward: Vector, name: str, quoins=None) -> dict:
    """A chamber behind the bridge entry; the bridge owns everything beyond it."""
    h=o.half; extent=h+THICKNESS
    centre=mouth-outward*extent;side=UP.cross(outward);reach=4*extent
    planes=[(centre+d*h,d) for d in (outward,side,-outward,-side)]
    def air(padding):
        chamber=clearance(o,centre,outward,-reach,reach,name+'_chamber',padding=padding)
        parts={0:[chamber]};clip_groups(parts,[(p+n*padding,n) for p,n in planes])
        del chamber['arch_clear']
        arrival=clearance(o,mouth,incoming,0,reach,name+'_arrival',padding=padding)
        # The skew tunnel enters the chamber, not the bridge-facing facade.
        parts={0:[arrival]};clip_groups(parts,[(mouth-outward*(THICKNESS-padding),outward)])
        del arrival['arch_clear']
        exit=clearance(exit_profile,mouth,outward,-THICKNESS-padding,THICKNESS,name+'_bridge_door',padding=padding)
        return [chamber,arrival,exit]
    openings=air(0)
    groups={}
    for k,d in enumerate((outward,side,-outward,-side)):
        along=d.cross(UP)
        front=[masonry.Opening(extent-exit_profile.half,extent+exit_profile.half,-.2,exit_profile.spring,
                               rise=exit_profile.crown-exit_profile.spring)] if k==0 else []
        parts=masonry.Wall(2*extent,o.crown+RING+.3,THICKNESS,front,
                           course=(.28,.4),stone=(.55,1.0)).build(lib,rng,quoins=quoins,name=name+'_wall',core=False)
        masonry.place(parts,centre+d*h-along*extent,along,UP)
        groups[k]=parts
    subtract(groups,openings)
    roof={0:_vault(rng,o,centre-outward*h,outward,2*h,name+'_roof')}
    clip_groups(roof,planes);subtract(roof,openings[1:]);groups[4]=roof[0]
    mass=box(name+'_mass',centre,outward,extent,-.15,o.crown+RING+.3);mass['tone']=-1
    recessed=air(RECESS);backing={0:[mass]};subtract(backing,recessed);groups[20]=backing[0]
    bed=box(name+'_bed',centre,outward,extent,-.45,-.12);bed['tone']=-1
    # Render bedding sits beneath chipped flags; walking collision meets the
    # existing flat root ribbon and the bridge start at the actual floor.
    bed['walking_surface_lift']=.12
    groups[24]=[bed]
    groups[21]=pave_field(lib,centre-outward*extent,outward,2*extent,extent,name+'_floor')
    for cutter in openings+recessed:core.discard(cutter)
    return groups


def portal(lib, rng, quoins, o: masonry.Opening, mouth: Vector, outward: Vector, name: str) -> dict:
    """A face wall with the passage's arch, its face through `mouth` (the
    floor centre where the open crossing starts), facing `outward`."""
    flank = 1.4
    outward = Vector((outward.x, outward.y, 0.0)).normalized()
    along = UP.cross(outward)
    opening = masonry.Opening(flank, flank + 2.0 * o.half, -0.2, o.spring, rise=o.crown - o.spring)
    wall = masonry.Wall(2.0 * (flank + o.half), o.crown + RING + 0.9, THICKNESS, [opening])
    pieces = wall.build(lib, rng, quoins=quoins, name=name)
    masonry.place(pieces, mouth - along * (flank + o.half), along, UP)
    return {0: pieces}
