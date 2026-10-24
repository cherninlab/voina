"""Pinned cloth panels simulated offline in Blender and baked to static meshes.

Extends the pinned-cloth bake of scripts/art/build_dungeon_structure.py with
ragged hems, tears, holes, moving pins, colliders and per-asset metrics.

A panel is a grid in metres. Grid point (column, row) has panel coordinates
u = column / columns * width (across) and v = row / rows * height (away from
the pinned edge) and starts at `place(u, v)` in Blender coordinates. UVs are
those metres, flipped so Godot reads UV = (u, v) with v growing away from the
pins. "Color" is per point: R = 1 until AO is baked, G = variation, B = edge
wear (1 on free edges, 0 from `wear_width` inwards). Pinned edges do not wear.

Each pin starts where the grid puts it and ends at its socket target. A shape
key drives pins from start to target over the first `gather` frames, so
gathering a banner between nails or pulling a web into a corner is part of the
simulated motion, and the settled pin positions are measured against the
sockets afterwards.

    panel = cloth.Panel('Banner', (1.0, 2.0), (24, 46), place, keep=mask)
    panel.tear(12, 40, 46)
    panel.pin(0, 0, target)
    obj = panel.build(front=Vector((0, -1, 0)))
    sim = cloth.simulate(obj, panel, cloth.CANVAS, frames=240, gather=30)
    cloth.thicken(obj, 0.004)
"""
import math
import time
from collections import deque

import bmesh
import bpy
from mathutils import Vector

# Cloth modifier presets. Tension is stiff (stretch must stay under 5%);
# compression is soft so gathered cloth buckles into folds instead of pushing
# the pins apart. Mass is per vertex in kilograms.
CANVAS = dict(quality=12, mass=0.3, tension_stiffness=220, compression_stiffness=20,
              shear_stiffness=20, bending_stiffness=0.5, air_damping=5.0)
LINEN = dict(quality=30, mass=0.1, tension_stiffness=500, compression_stiffness=15,
             shear_stiffness=15, bending_stiffness=0.25, air_damping=5.0)
WEB = dict(quality=16, mass=0.05, tension_stiffness=160, compression_stiffness=2,
           shear_stiffness=2, bending_stiffness=0.005, air_damping=12.0)


def smooth_noise(rng, count: int = 12):
    """1-D value noise on [0, 1] from `count` random knots, cosine-interpolated."""
    knots = [rng.uniform(-1.0, 1.0) for _ in range(count + 1)]

    def sample(t: float) -> float:
        x = min(max(t, 0.0), 1.0) * count
        i = min(int(x), count - 1)
        f = (1 - math.cos(math.pi * (x - i))) * 0.5
        return knots[i] * (1 - f) + knots[i + 1] * f
    return sample


def ragged_edge(rng, depth: float, notches: int = 0, notch_depth: float = 0.0, notch_width: float = 0.08,
                shape: str = 'straight', shape_depth: float = 0.0):
    """Hem line as metres cut from the free end, a function of u in [0, 1].
    `shape` adds a deliberate cut: 'swallowtail' (V into the cloth), 'point'
    (V out of it, cutting the corners) or 'straight'. Notches are short
    tears. Coarse and fine noise give the frayed edge."""
    coarse, fine = smooth_noise(rng, 7), smooth_noise(rng, 53)
    cuts = [(rng.uniform(0.08, 0.92), rng.uniform(0.5, 1.0) * notch_depth, notch_width * rng.uniform(0.5, 1.2))
            for _ in range(notches)]

    def cut(u: float) -> float:
        value = depth * (0.55 + 0.3 * coarse(u) + 0.3 * fine(u))
        if shape == 'swallowtail':
            value += shape_depth * (1 - abs(u - 0.5) * 2)
        elif shape == 'point':
            value += shape_depth * abs(u - 0.5) * 2
        for centre, deep, width in cuts:
            value += deep * max(0.0, 1 - abs(u - centre) / width)
        return max(value, 0.0)
    return cut


def blobs(rng, count: int, box, radius, avoid=None):
    """Ragged elliptical holes. `box` = (u0, v0, u1, v1) in metres where hole
    centres may fall, `radius` = (min, max). `avoid(u, v)` rejects centres.
    Returns inside(u, v)."""
    holes = []
    tries = 0
    while len(holes) < count and tries < 200:
        tries += 1
        u, v = rng.uniform(box[0], box[2]), rng.uniform(box[1], box[3])
        if avoid and avoid(u, v):
            continue
        holes.append((u, v, rng.uniform(*radius), rng.uniform(0.55, 1.0), rng.uniform(0, math.pi),
                      smooth_noise(rng, 9)))

    def inside(u: float, v: float) -> bool:
        for cu, cv, r, squash, angle, wobble in holes:
            du, dv = u - cu, v - cv
            x = du * math.cos(angle) + dv * math.sin(angle)
            y = (-du * math.sin(angle) + dv * math.cos(angle)) / squash
            theta = (math.atan2(y, x) / (2 * math.pi)) % 1.0
            if math.hypot(x, y) < r * (1 + 0.35 * wobble(theta)):
                return True
        return False
    inside.count = len(holes)
    return inside


class Panel:
    """Grid cloth with ragged outline, tears and pins; see module docstring."""

    def __init__(self, name: str, size, cells, place, keep=None, variation: float = 0.5,
                 wear_width: float = 0.08):
        self.name = name
        self.width, self.height = size
        self.cols, self.rows = cells
        self.variation = variation
        self.wear_width = wear_width
        self.place = place
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')
        self.color = self.bm.verts.layers.float_color.new('Color')
        # Panel coordinates ride along through tears; removed before export.
        self.pu = self.bm.verts.layers.float.new('panel_u')
        self.pv = self.bm.verts.layers.float.new('panel_v')
        self.grid = {}
        self.pins = []        # (BMVert, target Vector)
        self.tears = 0
        for row in range(self.rows + 1):
            for col in range(self.cols + 1):
                u, v = self.coords(col, row)
                vert = self.bm.verts.new(place(u, v))
                vert[self.pu], vert[self.pv] = u, v
                self.grid[(col, row)] = vert
        self.cells_kept = 0
        for row in range(self.rows):
            for col in range(self.cols):
                u, v = self.coords(col + 0.5, row + 0.5)
                if keep is not None and not keep(u, v):
                    continue
                corners = [(col, row), (col + 1, row), (col + 1, row + 1), (col, row + 1)]
                face = self.bm.faces.new([self.grid[k] for k in corners])
                for loop, k in zip(face.loops, corners):
                    cu, cv = self.coords(*k)
                    # glTF flips V; Godot then reads (u, v) in metres.
                    loop[self.uv].uv = (cu, 1.0 - cv)
                self.cells_kept += 1

    def coords(self, col: float, row: float):
        return col / self.cols * self.width, row / self.rows * self.height

    def vert(self, col: int, row: int) -> bmesh.types.BMVert:
        return self.grid[(col, row)]

    def tear(self, col: int, row0: int, row1: int) -> int:
        """Slit along grid column line `col` between rows row0..row1 (a tear
        running in from the hem). Only edges with cloth on both sides split."""
        edges = []
        for row in range(row0, row1):
            a, b = self.grid.get((col, row)), self.grid.get((col, row + 1))
            if a is None or b is None:
                continue
            edge = self.bm.edges.get((a, b))
            if edge is not None and len(edge.link_faces) == 2:
                edges.append(edge)
        if edges:
            bmesh.ops.split_edges(self.bm, edges=edges)
            self.tears += 1
        return len(edges)

    def pin(self, col: int, row: int, target: Vector) -> bmesh.types.BMVert:
        vert = self.grid[(col, row)]
        assert vert.link_faces, f'{self.name}: pin ({col}, {row}) has no cloth'
        self.pins.append((vert, Vector(target)))
        return vert

    def relax_outline(self, pinned: set, iterations: int) -> None:
        """Smooth the staircase of masked cells along free edges in panel
        space (u, v), then re-place those vertices and their UVs."""
        neighbours = {}
        for edge in self.bm.edges:
            if edge.is_boundary:
                a, b = edge.verts
                neighbours.setdefault(a, []).append(b)
                neighbours.setdefault(b, []).append(a)
        free = [v for v, n in neighbours.items() if v not in pinned and len(n) == 2]
        for _ in range(iterations):
            moved = []
            for vert in free:
                a, b = neighbours[vert]
                moved.append((vert, 0.5 * vert[self.pu] + 0.25 * (a[self.pu] + b[self.pu]),
                              0.5 * vert[self.pv] + 0.25 * (a[self.pv] + b[self.pv])))
            for vert, u, v in moved:
                vert[self.pu], vert[self.pv] = u, v
        for vert in free:
            u, v = vert[self.pu], vert[self.pv]
            vert.co = self.place(u, v)
            for loop in vert.link_loops:
                loop[self.uv].uv = (u, 1.0 - v)

    def build(self, front: Vector = None, relax: int = 2) -> bpy.types.Object:
        """Drop cloth not hanging from a pin, smooth the outline, colour, and
        make the object with a "Pins" group and a "Sockets" shape key (pins at
        their targets)."""
        bm = self.bm
        pinned = {vert for vert, _ in self.pins}
        assert pinned, f'{self.name}: no pins'
        # Cells held by fewer than two edges flap and never settle: erode them.
        self.cells_eroded = 0
        while True:
            loose = [face for face in bm.faces
                     if sum(len(edge.link_faces) == 2 for edge in face.edges) < 2
                     and not any(vert in pinned for vert in face.verts)]
            if not loose:
                break
            self.cells_eroded += len(loose)
            bmesh.ops.delete(bm, geom=loose, context='FACES_ONLY')
        reached, queue = set(), deque(face for vert in pinned for face in vert.link_faces)
        while queue:
            face = queue.popleft()
            if face in reached:
                continue
            reached.add(face)
            for edge in face.edges:
                queue.extend(f for f in edge.link_faces if f not in reached)
        dropped = [face for face in bm.faces if face not in reached]
        self.islands_dropped = len(dropped)
        bmesh.ops.delete(bm, geom=dropped, context='FACES_ONLY')
        bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        self.relax_outline(pinned, relax)
        # Triangles: every corner then has a bending hinge (a lone quad corner
        # flutters forever under angular bending). BEAUTY avoids the slivers
        # that the relaxed outline would otherwise leave, which also flutter.
        bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='BEAUTY')
        if front is not None:
            bm.normal_update()
            if sum((f.normal * f.calc_area() for f in bm.faces), Vector()).dot(front) < 0:
                bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        # Edge wear: walk inwards from free boundary vertices.
        distance = {}
        queue = []
        for edge in bm.edges:
            if edge.is_boundary:
                for vert in edge.verts:
                    if vert not in pinned and vert not in distance:
                        distance[vert] = 0.0
                        queue.append(vert)
        frontier = deque(queue)
        while frontier:
            vert = frontier.popleft()
            for edge in vert.link_edges:
                other = edge.other_vert(vert)
                d = distance[vert] + edge.calc_length()
                if d < self.wear_width and d < distance.get(other, math.inf):
                    distance[other] = d
                    frontier.append(other)
        for vert in bm.verts:
            wear = max(0.0, 1.0 - distance.get(vert, math.inf) / self.wear_width)
            vert[self.color] = (1.0, self.variation, wear, 1.0)
        bm.verts.index_update()
        bm.normal_update()
        self.pin_ids = [vert.index for vert, _ in self.pins]
        self.targets = [target for _, target in self.pins]
        # Removing a layer reallocates the elements: no BMVert is used after this.
        bm.verts.layers.float.remove(self.pu)
        bm.verts.layers.float.remove(self.pv)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.color_attributes.active_color = mesh.color_attributes['Color']
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        group = obj.vertex_groups.new(name='Pins')
        group.add(self.pin_ids, 1.0, 'REPLACE')
        obj.shape_key_add(name='Basis', from_mix=False)
        key = obj.shape_key_add(name='Sockets', from_mix=False)
        for index, target in zip(self.pin_ids, self.targets):
            key.data[index].co = target
        self.rest = [v.co.copy() for v in mesh.vertices]
        self.object = obj
        return obj


def collider(obj: bpy.types.Object, thickness: float = 0.003, friction: float = 20.0) -> bpy.types.Object:
    """Make `obj` a cloth collider (it is never exported). Full damping and
    high friction stop stick-slip jitter where cloth rests on it."""
    obj.modifiers.new('Collision', 'COLLISION')
    obj.collision.thickness_outer = thickness
    obj.collision.thickness_inner = 0.02
    obj.collision.cloth_friction = friction
    obj.collision.damping = 1.0
    return obj


def simulate(obj: bpy.types.Object, panel: Panel, preset: dict, frames: int = 240, gather: int = 30,
             fps: int = 30, collide: bool = False, distance: float = 0.003, self_collide: bool = False,
             collision_quality: int = 4, calm: tuple = None) -> dict:
    """Run the cloth modifier for `frames`, pins easing to their sockets over
    `gather` frames, then replace the object's mesh by the settled frame.
    `calm` = (frame, air_damping) ramps air damping up over one second from
    that frame, which stills contact jitter once the drape has formed.
    Returns metrics in Blender metres."""
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.frame_start, scene.frame_end = 1, frames
    key = obj.data.shape_keys.key_blocks['Sockets']
    key.value = 0.0
    key.keyframe_insert('value', frame=1)
    key.value = 1.0
    key.keyframe_insert('value', frame=max(2, gather))
    modifier = obj.modifiers.new('Cloth', 'CLOTH')
    settings = modifier.settings
    for name, value in preset.items():
        setattr(settings, name, value)
    settings.vertex_group_mass = 'Pins'
    settings.pin_stiffness = 1.0
    collision = modifier.collision_settings
    collision.use_collision = collide
    collision.distance_min = distance
    collision.collision_quality = collision_quality
    collision.use_self_collision = self_collide
    collision.self_distance_min = distance
    modifier.point_cache.frame_start = 1
    modifier.point_cache.frame_end = frames
    if calm is not None:
        path = f'modifiers["{modifier.name}"].settings.air_damping'
        obj.keyframe_insert(path, frame=calm[0])
        settings.air_damping = calm[1]
        obj.keyframe_insert(path, frame=calm[0] + fps)
    started = time.time()
    previous = final = None
    motion = []           # largest vertex move in the last frame of each second
    for frame in range(1, frames + 1):
        scene.frame_set(frame)
        if frame % fps == 0 or frame >= frames - 1:
            evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            current = [v.co.copy() for v in evaluated.data.vertices]
            if frame >= frames - 1:
                previous, final = final, current
            if frame % fps == 0 and frame > 1:
                scene.frame_set(frame - 1)
                before = [v.co.copy() for v in obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices]
                scene.frame_set(frame)
                motion.append(round(max((a - b).length for a, b in zip(current, before)), 6))
    seconds = time.time() - started
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    baked = bpy.data.meshes.new_from_object(evaluated)
    assert len(baked.vertices) == len(panel.rest), 'cloth changed topology'
    assert all(math.isfinite(c) for v in final for c in v), 'cloth exploded'
    metrics = measure(baked, panel.rest, final, panel.pin_ids, panel.targets)
    moves = [(a - b).length for a, b in zip(final, previous)]
    worst = max(range(len(moves)), key=moves.__getitem__)
    metrics.update(frames=frames, fps=fps, gather_frames=gather, sim_seconds=round(seconds, 2),
                   calm=list(calm) if calm else None,
                   settle_motion_m=moves[worst], settle_worst_rest=[round(c, 3) for c in panel.rest[worst]],
                   motion_per_second_m=motion)
    replace_mesh(obj, baked)
    return metrics


def measure(mesh: bpy.types.Mesh, rest: list, final: list, pin_ids: list, targets: list) -> dict:
    """Pin error against sockets and edge length ratios against the rest grid."""
    ratios = [(final[a] - final[b]).length / max((rest[a] - rest[b]).length, 1e-9)
              for a, b in (e.vertices for e in mesh.edges)]
    return {
        'max_pin_error_m': max((final[i] - t).length for i, t in zip(pin_ids, targets)),
        'max_edge_stretch': max(ratios),
        'min_edge_ratio': min(ratios),
        'lowest_z_m': min(p.z for p in final),
    }


def replace_mesh(obj: bpy.types.Object, mesh: bpy.types.Mesh) -> None:
    old = obj.data
    obj.modifiers.clear()
    obj.shape_key_clear()
    obj.vertex_groups.clear()
    obj.data = mesh
    mesh.name = old.name
    bpy.data.meshes.remove(old)
    if 'Color' in mesh.color_attributes:
        mesh.color_attributes.active_color = mesh.color_attributes['Color']


def thicken(obj: bpy.types.Object, thickness: float) -> None:
    """Centred solidify (pins stay on the mid surface), applied, smooth shaded.
    Even offset is off: it shoots spikes out of tight folds."""
    before = bounds(obj)
    modifier = obj.modifiers.new('FabricThickness', 'SOLIDIFY')
    modifier.thickness = thickness
    modifier.offset = 0.0
    modifier.use_even_offset = False
    modifier.use_quality_normals = True
    modifier.use_rim = True
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    replace_mesh(obj, bpy.data.meshes.new_from_object(evaluated))
    after = bounds(obj)
    growth = max(max(b0 - a0, a1 - b1) for (a0, a1), (b0, b1) in zip(after, before))
    assert growth <= thickness, f'{obj.name}: solidify grew the bounds by {growth} m'
    smooth(obj)


def bounds(obj: bpy.types.Object) -> list:
    coords = [v.co for v in obj.data.vertices]
    return [(min(c[i] for c in coords), max(c[i] for c in coords)) for i in range(3)]


def smooth(obj: bpy.types.Object) -> None:
    obj.data.polygons.foreach_set('use_smooth', [True] * len(obj.data.polygons))
    obj.data.update()


def triangles(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)
