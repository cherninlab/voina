"""Finish the first upper-crossing assets without rebaking the dungeon.

Run in Blender 5.2:
  blender -b --python-exit-code 1 --python scripts/art/build_upper_crossing.py

The gallery retains the imported stone faces and collision meshes, caps hidden
backs, and bonds each section around a connected cement core with open doorways.
"""
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_architecture as architecture
from procgen import core, export, masonry, stonelib, stones

OUT = core.ROOT / "content/environments/red_descent/upper_crossing_v1"
SOURCE = core.ROOT / "content/environments/procedural_architecture_v1/passages/return_gallery.glb"


def coordinates(objects):
    return {
        obj.name: sorted(tuple(round(value, 5) for value in obj.matrix_world @ vertex.co)
                         for vertex in obj.data.vertices)
        for obj in objects
    }


def cap_mass(obj, centre, side, radius, spring_angle):
    """Intersect the original mass with tangent planes outside the intrados."""
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    bmesh.ops.remove_doubles(mesh, verts=list(mesh.verts), dist=0.00001)
    protected = [
        vertex.co.copy() for vertex in mesh.verts
        if vertex.co.z < -7.65 or
        math.hypot((vertex.co - centre).dot(side), vertex.co.z - centre.z) < radius - 0.3
    ]
    for index in range(19):
        angle = spring_angle + (math.pi - 2 * spring_angle) * index / 18.0
        radial = side * math.cos(angle) + Vector((0, 0, math.sin(angle)))
        result = bmesh.ops.bisect_plane(
            mesh, geom=list(mesh.verts) + list(mesh.edges) + list(mesh.faces),
            plane_co=centre + radial * radius, plane_no=radial,
            clear_outer=True, dist=0.00001,
        )
        edges = [edge for edge in result["geom_cut"] if isinstance(edge, bmesh.types.BMEdge)]
        if edges:
            caps = bmesh.ops.holes_fill(mesh, edges=edges, sides=0)["faces"]
            # New cap loops otherwise default to black, which makes a solid
            # shoulder read as an open slit in the game.
            for layer in list(mesh.loops.layers.float_color.values()) + list(mesh.loops.layers.color.values()):
                for face in caps:
                    for loop in face.loops:
                        loop[layer] = (0.72, 0.72, 0.72, 1.0)
    bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    assert all(edge.is_manifold for edge in mesh.edges), obj.name
    retained = {tuple(round(value, 5) for value in vertex.co) for vertex in mesh.verts}
    assert all(tuple(round(value, 5) for value in point) in retained for point in protected), obj.name
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()
    obj.data.calc_loop_triangles()
    obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
    for face in obj.data.polygons:
        face.use_smooth = False
    return len(protected)


def rebuild_cement(target, profile, origin, direction, side, start, end, planes):
    """One connected cement tube with an open passage and a recessed solid floor.

    End vertices are solved directly on the source mitre planes. No capping
    operation may accidentally fill the doorway or leave two touching shells.
    """
    recess = 0.034
    hole = masonry.Opening(-profile.half - recess, profile.half + recess, spring=profile.spring,
                           rise=profile.crown - profile.spring + recess)
    half = profile.half + 0.94 - recess
    outer_radius = profile.radius + 0.52
    corner = profile.cy + (outer_radius - half * math.cos(profile.a0)) / math.sin(profile.a0)
    outer = [(-half, -0.34), (half, -0.34), (half, corner)]
    outer += [(outer_radius * math.cos(t), profile.cy + outer_radius * math.sin(t)) for t in [profile.a0 + (math.pi - 2 * profile.a0) * k / 22 for k in range(23)]]
    outer += [(-half, corner)]
    inner = [(-hole.half, -0.06), (hole.half, -0.06)]
    inner += [(hole.radius * math.cos(t), hole.cy + hole.radius * math.sin(t)) for t in [hole.a0 + (math.pi - 2 * hole.a0) * k / 24 for k in range(25)]]
    assert len(inner) == len(outer)
    n = len(inner)
    vertices = []
    for back in (False, True):
        for contour in (outer, inner):
            for x, z in contour:
                offset = side * x + Vector((0, 0, z))
                low, high = start - 0.05, end + 0.05
                for point, normal in planes:
                    denominator = direction.dot(normal)
                    assert abs(denominator) > 0.01
                    limit = (point - origin - offset).dot(normal) / denominator
                    if denominator > 0:
                        high = min(high, limit)
                    else:
                        low = max(low, limit)
                assert high > low + 0.001, target.name
                vertices.append(tuple(origin + offset + direction * (high if back else low)))
    faces = []
    for k in range(n):
        j = (k + 1) % n
        faces += [(k, j, j + 2*n, k + 2*n), (k+n, k+3*n, j+3*n, j+n),
                  (k, k+n, j+n, j), (k+2*n, j+2*n, j+3*n, k+3*n)]
    data = bpy.data.meshes.new(target.name + "_solid_cement")
    data.from_pydata(vertices, [], faces)
    shell = bmesh.new(); shell.from_mesh(data)
    bmesh.ops.triangulate(shell, faces=list(shell.faces))
    bmesh.ops.recalc_face_normals(shell, faces=list(shell.faces))
    assert all(edge.is_manifold for edge in shell.edges), target.name
    shell.to_mesh(data); shell.free()
    data.update()
    colour = data.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
    for item in colour.data:
        item.color = (0.72, 0.72, 0.72, 1)
    data.color_attributes.active_color = colour
    target.data = data


def export_bonded_gallery(objects, roof, facing, collisions):
    """One render object per passage section, with stone and cement surfaces."""
    stone_material = bpy.data.materials.new("GalleryStone")
    mortar_material = bpy.data.materials.new("GalleryMortar")
    groups = []
    for segment in range(5):
        original = [obj for obj in objects if obj not in collisions and int(obj.name.rsplit("_", 1)[1]) // 5 == segment]
        extra = [obj for obj in roof + facing if int(obj.name.rsplit("_", 1)[1]) == segment]
        groups.append(original + extra)
    joined = []
    for segment, pieces in enumerate(groups):
        for obj in pieces:
            if not obj.name.startswith("Mortar"):
                # The legacy interior libraries deliberately omitted hidden
                # backs. Close them before packaging the bonded wall object.
                shell = bmesh.new(); shell.from_mesh(obj.data)
                bmesh.ops.remove_doubles(shell, verts=list(shell.verts), dist=0.000001)
                boundary = {edge for edge in shell.edges if edge.is_boundary}
                caps = []
                # Jagged backs are nonplanar. A generic ngon fill can reuse
                # visible stone diagonals and create nonmanifold edges. Give
                # each closed boundary its own hidden centre and triangle fan.
                while boundary:
                    edge = next(iter(boundary))
                    start = current = edge.verts[0]
                    loop = []
                    while True:
                        loop.append(current)
                        boundary.remove(edge)
                        current = edge.other_vert(current)
                        if current == start:
                            break
                        choices = [candidate for candidate in current.link_edges if candidate in boundary]
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
                assert all(edge.is_manifold for edge in shell.edges), obj.name
                shell.to_mesh(obj.data); shell.free()
                obj.data.update(); obj.data.calc_loop_triangles()
                obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
                for face in obj.data.polygons:
                    face.use_smooth = False
            material = mortar_material if obj.name.startswith("Mortar") else stone_material
            obj.data.materials.clear(); obj.data.materials.append(material)
            for face in obj.data.polygons:
                face.material_index = 0
        core.select_only(pieces)
        bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = f"BondedGallery_{segment}"
        joined.append(obj)
    core.select_only(joined + collisions)
    bpy.ops.export_scene.gltf(filepath=str(OUT / "gallery.glb"), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_texcoords=True, export_normals=True,
        export_vertex_color="NAME", export_vertex_color_name="Color", export_all_vertex_colors=False,
        export_materials="EXPORT", export_animations=False, export_extras=True)


def gallery():
    core.empty_scene()
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in objects:
        matrix = obj.matrix_world.copy()
        obj.parent = None
        obj.data.transform(matrix)
        obj.matrix_world = Matrix.Identity(4)
    collisions = [obj for obj in objects if obj.name.startswith("Collision")]
    before = coordinates(collisions)
    layout = json.loads((core.ROOT / "content/environments/procedural_bridge_v1/layout.json").read_text())
    route = next(route for route in layout["routes"] if route["id"] == "return_gallery")
    profile = architecture.profile(route, layout)
    rng = core.rng(20261107, "upper-gallery")
    runs, nodes = architecture.network(layout)
    wall_library = stonelib.Library(core.rng(20261107, "gallery-facing"), "squared_rubble", count=8, triangles=140)
    facings = []
    roofs = []
    protected = 0
    for segment, (p, q) in enumerate(zip(route["points"], route["points"][1:])):
        a = core.to_blender(p)
        b = core.to_blender(q)
        direction = (b - a).normalized()
        stretch_number, stretch = next((number, stretch) for number, stretch in enumerate(runs[route["id"]]) if stretch is not None and stretch[0] == segment)
        planes, _ = architecture.run_planes(route, stretch_number, stretch, nodes)
        side = direction.cross(Vector((0, 0, 1)))
        centre = a + Vector((0, 0, profile.cy))
        mass = next(obj for obj in objects if obj.name == f"Mortar_return_gallery_{segment * 5 + 3}")
        protected += cap_mass(mass, centre, side, profile.radius + 0.52, profile.a0)
        # Use the actual clipped longitudinal extent of the imported mass.
        along = [(vertex.co - a).dot(direction) for vertex in mass.data.vertices]
        start, end = min(along), max(along)
        rows = max(1, math.ceil((end - start) / 0.72))
        row_width = (end - start) / rows
        sweep = math.pi - 2 * profile.a0
        count = math.ceil(sweep * (profile.radius + 0.6) / 0.58)
        frame = Matrix((side, direction, Vector((0, 0, 1)))).transposed().to_4x4()
        for row in range(rows):
            for number in range(-1, count):
                angle = max(profile.a0, profile.a0 + (number + 0.5 * (row % 2)) * sweep / count)
                finish = min(math.pi - profile.a0, profile.a0 + (number + 1 + 0.5 * (row % 2)) * sweep / count)
                if finish - angle < 0.01:
                    continue
                piece = stones.voussoir(
                    rng, inner=profile.radius + 0.47, depth=rng.uniform(0.18, 0.24),
                    angle=(finish - angle) * 0.985, thickness=row_width - 0.012,
                    start=angle, name=f"roof_arch_{segment}_{row}_{number}", triangles=110,
                )
                origin = centre + direction * (start + (row + 0.5) * row_width)
                piece.matrix_world = Matrix.Translation(origin) @ frame @ piece.matrix_world
                piece["gallery_segment"] = segment
                piece["tone"] = rng.uniform(0.68, 1.02)
                piece["frame"] = [*direction, 0.0, 0.0, 1.0, *side]
                if all(masonry.clip(piece, point, normal) for point, normal in planes):
                    roofs.append(piece)
                else:
                    core.discard(piece)
        # Bond the visible exterior sides in the same planes as the source
        # passage. The interior lining and collision remain the imported ones.
        for sign in (-1, 1):
            outward = side * sign
            along_axis = direction if direction.cross(Vector((0, 0, 1))).dot(outward) > 0 else -direction
            base = a + direction * (start if along_axis.dot(direction) > 0 else end) + outward * (profile.half + 0.94) - Vector((0, 0, 0.32))
            facing = masonry.Wall(end - start, profile.spring + 0.32, thickness=0.36, joint=(0.008, 0.014))
            pieces = facing.build(wall_library, rng, name=f"gallery_exterior_{segment}_{sign}", core=False)
            masonry.place(pieces, base, along_axis, Vector((0, 0, 1)))
            for piece in pieces:
                trim = list(planes)
                for k in range(19):
                    angle = profile.a0 + sweep * k / 18
                    radial = side * math.cos(angle) + Vector((0, 0, math.sin(angle)))
                    trim.append((centre + radial * (profile.radius + 0.62), radial))
                if all(masonry.clip(piece, point, normal) for point, normal in trim):
                    piece["gallery_segment"] = segment
                    facings.append(piece)
                else:
                    core.discard(piece)
        rebuild_cement(mass, profile, a, direction, side, start, end, planes)
    roof = architecture.merge("upper_gallery_roof", {segment: [piece for piece in roofs if piece["gallery_segment"] == segment] for segment in range(5)}, rng)
    facing = architecture.merge("gallery_exterior", {segment: [piece for piece in facings if piece["gallery_segment"] == segment] for segment in range(5)}, rng)
    # The exterior shares the existing grey limestone, rather than arch sandstone.
    for obj in roof + facing:
        obj.name = obj.name.replace("Stone-arch_", "Stone-stone_")
        # merge() encodes tone/freshness for the later AO bake. This small
        # exterior addition has no AO bake, so export its per-stone grey tone
        # directly, rather than leaking the yellow intermediate mask.
        for item in obj.data.color_attributes["Color"].data:
            grey = item.color[1] * 1.25
            item.color = (grey, grey, grey, 1.0)
        triangles = bmesh.new(); triangles.from_mesh(obj.data)
        bmesh.ops.triangulate(triangles, faces=list(triangles.faces))
        bmesh.ops.recalc_face_normals(triangles, faces=list(triangles.faces))
        triangles.to_mesh(obj.data); triangles.free()
        obj.data.update(); obj.data.calc_loop_triangles()
        obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
        for face in obj.data.polygons:
            face.use_smooth = False
    assert coordinates(collisions) == before, "Original collision changed"
    roof_triangles = sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in roof)
    export_bonded_gallery(objects, roof, facing, collisions)
    report = {
        "source_sha256": core.sha256(SOURCE),
        "source_routes": next(entry["routes"] for entry in json.loads(
            (core.ROOT / "content/environments/procedural_architecture_v1/index.json").read_text()
        )["files"] if entry["file"] == "passages/return_gallery.glb"),
        "collision_meshes": len(collisions),
        "collision_vertex_coordinates_unchanged": True,
        "cap_preserved_interior_vertices_before_bonding": protected,
        "bonded_cement_shells": 5,
        "render_objects": 5,
        "cement_floor_recess_m": 0.06,
        "cement_floor_thickness_m": 0.28,
        "profile": {"spring_m": profile.spring, "rise_m": profile.crown - profile.spring,
                    "intrados_radius_m": profile.radius},
        "roof_stones": len(roofs),
        "exterior_facing_stones": len(facings),
        "roof_and_facing_mitres": "authoritative run_planes from the source passage network",
        "roof_bond": "alternating half-stone circumferential offsets",
        "roof_triangles": roof_triangles,
        "operation": "Preserve source collision and visible stone faces; cap hidden backs, rebuild connected cement and bond each section.",
    }
    (OUT / "gallery-build.json").write_text(json.dumps(report, indent=2) + "\n")
    print("UPPER_GALLERY_BUILT", json.dumps(report), flush=True)



def prism(name, polygon, floor, top):
    count = len(polygon)
    vertices = [(x, y, floor) for x, y in polygon] + [(x, y, top) for x, y in polygon]
    faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    faces += [(i, (i + 1) % count, (i + 1) % count + count, i + count) for i in range(count)]
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = core.link(bpy.data.objects.new(name, data))
    mesh = bmesh.new()
    mesh.from_mesh(data)
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    mesh.to_mesh(data)
    mesh.free()
    return obj


def clearances(layout):
    """Actual room roofs and arched passage envelopes, with route clearance."""
    cutters = []
    tops = json.loads((core.ROOT / "content/environments/procedural_architecture_v1/index.json").read_text())["tops"]
    for room in layout["rooms"]:
        plan = architecture.ccw([architecture.flat(point) for point in room["points"]])
        polygon = architecture.outset(plan, 0.65)
        cutters.append(prism("RoomClearance", polygon, room["floor"] - 0.08, tops.get(room["id"], room["floor"] + room["height"]) + 0.15))
    for route in layout["routes"]:
        for p, q in zip(route["points"], route["points"][1:]):
            a, b = core.to_blender(p), core.to_blender(q)
            axis = b - a
            axis.z = 0
            length = axis.length
            axis.normalize()
            side = axis.cross(Vector((0, 0, 1)))
            if route["enclosed"]:
                profile = architecture.profile(route, layout)
                radius = profile.radius + 0.78
                half = min(profile.half + 1.05, radius - 0.01)
                angle = math.acos(half / radius)
                section = [(-half, -0.2), (half, -0.2)]
                section += [(radius * math.cos(t), profile.cy + radius * math.sin(t)) for t in [angle + (math.pi - 2 * angle) * k / 24 for k in range(25)]]
                vertices = []
                for at, extend in [(a, -0.8), (b, 0.8)]:
                    origin = at + axis * extend + Vector((0, 0, (b.z - a.z) * extend / length))
                    vertices += [tuple(origin + side * x + Vector((0, 0, z))) for x, z in section]
                n = len(section)
                faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
                faces += [(k, (k + 1) % n, (k + 1) % n + n, k + n) for k in range(n)]
                data = bpy.data.meshes.new("VaultClearance")
                data.from_pydata(vertices, [], faces)
                obj = core.link(bpy.data.objects.new("VaultClearance", data))
                shell = bmesh.new(); shell.from_mesh(data)
                bmesh.ops.recalc_face_normals(shell, faces=list(shell.faces))
                shell.to_mesh(data); shell.free()
                cutters.append(obj)
            else:
                side *= route["width"] * 0.5 + 0.9
                front, back = a - axis * 0.8, b + axis * 0.8
                polygon = [(point.x, point.y) for point in [front - side, back - side, back + side, front + side]]
                cutters.append(prism("RouteClearance", polygon, min(a.z, b.z) - 0.2, max(a.z, b.z) + 3.5))
    return cutters


def carve(obj, cutters):
    """Subtract only overlapping clearance volumes, then validate the closed solid."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    low = Vector(tuple(min(vertex.co[i] for vertex in obj.data.vertices) for i in range(3)))
    high = Vector(tuple(max(vertex.co[i] for vertex in obj.data.vertices) for i in range(3)))
    for cutter in cutters:
        points = [vertex.co for vertex in cutter.data.vertices]
        if any(low[i] > max(point[i] for point in points) or high[i] < min(point[i] for point in points) for i in range(3)):
            continue
        difference = obj.modifiers.new("PlayableVolume", "BOOLEAN")
        difference.object = cutter
        difference.operation = "DIFFERENCE"
        difference.solver = "EXACT"
        bpy.ops.object.modifier_apply(modifier=difference.name)
        if len(obj.data.polygons) == 0:
            core.discard(obj)
            return False
    mesh = bmesh.new(); mesh.from_mesh(obj.data)
    bmesh.ops.remove_doubles(mesh, verts=list(mesh.verts), dist=0.00001)
    bmesh.ops.dissolve_degenerate(mesh, edges=list(mesh.edges), dist=0.000001)
    boundary = [edge for edge in mesh.edges if edge.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(mesh, edges=boundary, sides=0)
    bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    assert all(edge.is_manifold for edge in mesh.edges), obj.name
    mesh.to_mesh(obj.data); mesh.free()
    obj.data.update(); obj.data.calc_loop_triangles()
    for face in obj.data.polygons:
        face.use_smooth = False
    obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
    return True


def rock():
    core.empty_scene()
    bpy.ops.import_scene.gltf(filepath=str(OUT / "rock_lod0.glb"))
    source = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    source.data.transform(source.matrix_world)
    source.matrix_world = Matrix.Identity(4)
    layout = json.loads((core.ROOT / "content/environments/procedural_bridge_v1/layout.json").read_text())
    cutters = clearances(layout)
    rocks = []
    discarded_islands = 0
    for index, (at, height, angle) in enumerate([
        ((25.8, -15.0, -3.5), 11.0, 0.2),
        ((25.6, -5.0, -3.0), 11.0, -0.55),
        ((25.9, 4.0, -2.5), 9.0, 0.75),
    ]):
        obj = source.copy()
        obj.data = source.data.copy()
        obj.name = f"UpperRockCliff_{index}"
        core.link(obj)
        obj.matrix_world = Matrix.Translation(core.to_blender(at)) @ Matrix.Rotation(angle, 4, "Z") @ Matrix.Scale(height, 4)
        # Bake only visual vertices. No physics body or collision shape is scaled.
        obj.data.transform(obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        low = Vector(tuple(min(vertex.co[i] for vertex in obj.data.vertices) for i in range(3)))
        high = Vector(tuple(max(vertex.co[i] for vertex in obj.data.vertices) for i in range(3)))
        for cutter in cutters:
            vertices = [vertex.co for vertex in cutter.data.vertices]
            c_low = Vector(tuple(min(point[i] for point in vertices) for i in range(3)))
            c_high = Vector(tuple(max(point[i] for point in vertices) for i in range(3)))
            if any(low[i] > c_high[i] or high[i] < c_low[i] for i in range(3)):
                continue
            difference = obj.modifiers.new("PreservePlayableVolume", "BOOLEAN")
            difference.object = cutter
            difference.operation = "DIFFERENCE"
            difference.solver = "EXACT"
            bpy.ops.object.modifier_apply(modifier=difference.name)
        # Boolean cuts may inherit seams from the inferred shell. Rebuild a
        # closed surface after placement, then require manifold edges.
        obj.data.remesh_voxel_size = 0.055
        obj.data.remesh_voxel_adaptivity = 0.0
        bpy.ops.object.voxel_remesh()
        triangles = sum(len(face.vertices) - 2 for face in obj.data.polygons)
        reduce = obj.modifiers.new("PlacementBudget", "DECIMATE")
        reduce.ratio = min(1.0, 14000 / triangles)
        reduce.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=reduce.name)
        shell = bmesh.new()
        shell.from_mesh(obj.data)
        bmesh.ops.remove_doubles(shell, verts=list(shell.verts), dist=0.00001)
        bmesh.ops.dissolve_degenerate(shell, edges=list(shell.edges), dist=0.00001)
        boundary = [edge for edge in shell.edges if edge.is_boundary]
        if boundary:
            bmesh.ops.holes_fill(shell, edges=boundary, sides=0)
        bmesh.ops.triangulate(shell, faces=list(shell.faces))
        pending = set(shell.verts)
        components = []
        while pending:
            component = {pending.pop()}
            frontier = list(component)
            while frontier:
                vertex = frontier.pop()
                for edge in vertex.link_edges:
                    other = edge.other_vert(vertex)
                    if other in pending:
                        pending.remove(other); component.add(other); frontier.append(other)
            components.append(component)
        largest = max(components, key=lambda group: sum(face.calc_area() for face in {face for vertex in group for face in vertex.link_faces}))
        discarded_islands += len(components) - 1
        bmesh.ops.delete(shell, geom=list(set(shell.verts) - largest), context="VERTS")
        bmesh.ops.recalc_face_normals(shell, faces=list(shell.faces))
        assert all(edge.is_manifold for edge in shell.edges), obj.name
        shell.to_mesh(obj.data)
        shell.free()
        obj.data.update()
        obj.data.calc_loop_triangles()
        obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
        for face in obj.data.polygons:
            face.use_smooth = False
        rocks.append(obj)
    export.glb(rocks, OUT / "rock_cliff.glb")
    report = {
        "source": "rock_lod0.glb",
        "instances": len(rocks),
        "detached_components_removed": discarded_islands,
        "clearance_profile": "arched passage envelope; room support retained to 0.08m below floors",
        "boundary_edges": 0,
        "nonmanifold_edges": 0,
        "triangles": sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in rocks),
        "collision": "none; existing shaft collision is retained",
        "clearance": "Room walls offset 0.65m, enclosed passage arch grown 0.78m, open route ribbons offset 0.9m; room floor bearing retained.",
    }
    (OUT / "rock-placement.json").write_text(json.dumps(report, indent=2) + "\n")
    print("ROCK_CLIFF_BUILT", json.dumps(report), flush=True)


def structure_assets():
    """Closed relief and load paths on the east side of the actual shaft."""
    core.empty_scene()
    layout_path = core.ROOT / "content/environments/procedural_bridge_v1/layout.json"
    layout = json.loads(layout_path.read_text())
    cutters = clearances(layout)
    outline = [architecture.flat(point) for point in layout["outline"]]
    # The source outline is clockwise in Blender. Inward offsets are explicit
    # so source indices stay identical to the runtime wall indices.
    area = sum(a.x * b.y - a.y * b.x for a, b in zip(outline, outline[1:] + outline[:1]))
    normals = []
    for a, b in zip(outline, outline[1:] + outline[:1]):
        d = (b - a).normalized()
        normals.append(Vector((d.y, -d.x)) * (1 if area > 0 else -1))
    mitres = [(normals[i - 1] + normals[i]) / (1 + normals[i - 1].dot(normals[i])) for i in range(len(outline))]
    objects = []
    indices = [3, 4, 5, 6]
    for index in indices:
        a, b = outline[index], outline[(index + 1) % len(outline)]
        span = (b - a).length
        chunks = max(1, math.ceil(span / 8))
        for chunk in range(chunks):
            t0, t1 = chunk / chunks, (chunk + 1) / chunks
            steps = max(2, math.ceil(span / chunks))
            for band in range(6):
                low, high = -48 + 62 * band / 6, -48 + 62 * (band + 1) / 6
                rows = max(2, math.ceil(high - low))
                vertices = []
                for back in (False, True):
                    for row in range(rows + 1):
                        z = low + (high - low) * row / rows
                        for col in range(steps + 1):
                            t = t0 + (t1 - t0) * col / steps
                            point = a.lerp(b, t)
                            offset = mitres[index].lerp(mitres[(index + 1) % len(outline)], t)
                            sample = Vector((point.x, point.y, z))
                            depth = 0.95 + 0.2 * noise.noise(sample * 0.38) + 0.10 * noise.noise(sample * 1.4) + 0.07 * math.sin(z * 1.7 + point.x * 0.3)
                            point += offset * (0.9 if back else -depth)
                            vertices.append((point.x, point.y, z))
                size = (rows + 1) * (steps + 1)
                faces = []
                for row in range(rows):
                    for col in range(steps):
                        q = row * (steps + 1) + col
                        faces.append((q, q + 1, q + steps + 2, q + steps + 1))
                        faces.append((q + size, q + steps + 1 + size, q + steps + 2 + size, q + 1 + size))
                boundary = list(range(steps + 1))
                boundary += [row * (steps + 1) + steps for row in range(1, rows + 1)]
                boundary += list(range(rows * (steps + 1) + steps - 1, rows * (steps + 1) - 1, -1))
                boundary += [row * (steps + 1) for row in range(rows - 1, 0, -1)]
                faces += [(q, boundary[(k + 1) % len(boundary)], boundary[(k + 1) % len(boundary)] + size, q + size) for k, q in enumerate(boundary)]
                data = bpy.data.meshes.new("ShaftRelief")
                data.from_pydata(vertices, [], faces)
                obj = core.link(bpy.data.objects.new(f"ShaftRock_{index}_{chunk}_{band}", data))
                shell = bmesh.new(); shell.from_mesh(data)
                bmesh.ops.triangulate(shell, faces=list(shell.faces))
                bmesh.ops.recalc_face_normals(shell, faces=list(shell.faces))
                shell.to_mesh(data); shell.free()
                if carve(obj, cutters):
                    objects.append(obj)
    # A real thickness under the room floors closes their open perimeter
    # between the stone facade and its former single underside plane.
    for room in layout["rooms"]:
        if room["id"] not in ["restraint", "cells", "first_stair_hall"]:
            continue
        polygon = architecture.outset(architecture.ccw([architecture.flat(point) for point in room["points"]]), 0.50)
        obj = prism("Foundation_" + room["id"], polygon, room["floor"] - 0.65, room["floor"] - 0.015)
        # Own room is above this plinth. Keep its floor support while cutting
        # every other playable volume, including lower rooms and stairs.
        if carve(obj, cutters[len(layout["rooms"]):]):
            objects.append(obj)
    bpy.ops.wm.obj_import(filepath=str(core.ROOT / "content/environments/dungeon_masonry_v1/pier.obj"), forward_axis="NEGATIVE_Z", up_axis="Y")
    source = bpy.context.view_layer.objects.active
    source.data.transform(source.matrix_world)
    source.matrix_world = Matrix.Identity(4)
    pier_template = source.data.copy()
    core.discard(source)
    centres = [(24.4, 10), (23.4, -1), (22.4, -14), (24.4, -24)]
    for index, (x, z) in enumerate(centres):
        obj = core.link(bpy.data.objects.new(f"Support_Pier_{index}", pier_template.copy()))
        obj.data.transform(Matrix.Translation(core.to_blender((x, -29.25, z))) @ Matrix.Diagonal((2.0, 2.2, 37.5, 1)))
        if carve(obj, cutters):
            objects.append(obj)
    # Segmental masonry arches transfer the gallery to its piers. This uses
    # the same wall/ring builder as the project's passage interiors.
    rng = core.rng(20261107, "gallery-supports")
    library = stonelib.Library(rng, "squared_rubble", count=8, triangles=140)
    arch_parts = []
    for index, (p, q) in enumerate(zip(centres, centres[1:])):
        a, b = core.to_blender((p[0], 0, p[1])), core.to_blender((q[0], 0, q[1]))
        along = (b - a).normalized()
        length = (b - a).length
        rise = min((length - 2.0) * 0.45, 4.7)
        o = masonry.Opening(0.9, length - 0.9, spring=0.0, rise=rise)
        wall = masonry.Wall(length, rise + 0.72, thickness=2.0, openings=[o], ring=0.55, joint=(0.008, 0.014))
        pieces = wall.build(library, rng, name=f"support_arch_{index}")
        masonry.place(pieces, a + Vector((0, 0, -10.48 - rise - 0.72)), along, Vector((0, 0, 1)))
        for piece in pieces:
            piece.data = piece.data.copy()
            piece.data.transform(piece.matrix_world)
            piece.matrix_world = Matrix.Identity(4)
            if carve(piece, cutters):
                arch_parts.append(piece)
    groups = architecture.merge("support_arch", {0: arch_parts}, rng)
    for obj in groups:
        obj.name = obj.name.replace("Stone-arch_", "Stone-stone_")
        if obj.name.startswith("Stone"):
            for item in obj.data.color_attributes["Color"].data:
                grey = item.color[1] * 1.25
                item.color = (grey, grey, grey, 1)
        else:
            obj.name = "Support_" + obj.name
            for item in obj.data.color_attributes["Color"].data:
                item.color = (0.42, 0.42, 0.42, 1)
        objects.append(obj)
    export.glb(objects, OUT / "structure.glb")
    report = {"outline": layout["outline"], "routes": {route["id"]: route["layout_hash"] for route in layout["routes"]},
              "rooms": [{k: room[k] for k in ["id", "floor", "height", "points"]} for room in layout["rooms"]],
              "wall_indices": indices, "mesh_count": len(objects), "source_layout_sha256": core.sha256(layout_path),
              "triangles": sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in objects),
              "method": "Closed relief solids, room floor plinths, continuous project pier geometry and masonry arches; all carved outside playable envelopes",
              "collision": "New relief/support collision follows the carved render meshes; existing route and gallery collision preserved"}
    (OUT / "structure-build.json").write_text(json.dumps(report, indent=2) + "\n")
    print("STRUCTURE_BUILT", json.dumps({k:v for k,v in report.items() if k not in ["outline", "routes", "rooms"]}), flush=True)


if __name__ == "__main__":
    arguments = core.args()
    if not arguments or "--gallery-only" in arguments:
        gallery()
    if not arguments or "--rock-only" in arguments:
        rock()
    if not arguments or "--structure-only" in arguments:
        structure_assets()
