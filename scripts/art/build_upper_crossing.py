"""Finish the first upper-crossing assets without rebaking the dungeon.

Run in Blender 5.2:
  blender -b --python-exit-code 1 --python scripts/art/build_upper_crossing.py

The gallery keeps the imported interior, paving, and collision meshes. Only
its exterior mortar is trimmed to the vault profile, then given roof stones.
"""
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_architecture as architecture
from procgen import core, export, stones

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
            bmesh.ops.holes_fill(mesh, edges=edges, sides=0)
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
    roofs = []
    protected = 0
    for segment, (p, q) in enumerate(zip(route["points"], route["points"][1:])):
        a = core.to_blender(p)
        b = core.to_blender(q)
        direction = (b - a).normalized()
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
            for number in range(count):
                angle = profile.a0 + number * sweep / count
                piece = stones.voussoir(
                    rng, inner=profile.radius + 0.50, depth=rng.uniform(0.12, 0.18),
                    angle=sweep / count * 0.975, thickness=row_width - 0.018,
                    start=angle, name=f"roof_arch_{segment}_{row}_{number}", triangles=70,
                )
                origin = centre + direction * (start + (row + 0.5) * row_width)
                piece.matrix_world = Matrix.Translation(origin) @ frame @ piece.matrix_world
                piece["tone"] = rng.uniform(0.68, 1.02)
                piece["frame"] = [*direction, 0.0, 0.0, 1.0, *side]
                roofs.append(piece)
    roof = architecture.merge("upper_gallery_roof", {0: roofs}, rng)
    # The exterior shares the existing grey limestone, rather than arch sandstone.
    for obj in roof:
        obj.name = obj.name.replace("Stone-arch_", "Stone-stone_")
        # merge() encodes tone/freshness for the later AO bake. This small
        # exterior addition has no AO bake, so export its per-stone grey tone
        # directly, rather than leaking the yellow intermediate mask.
        for item in obj.data.color_attributes["Color"].data:
            grey = item.color[1] * 1.25
            item.color = (grey, grey, grey, 1.0)
    assert coordinates(collisions) == before, "Original collision changed"
    export.glb(objects + roof, OUT / "gallery.glb")
    report = {
        "source_sha256": core.sha256(SOURCE),
        "source_routes": next(entry["routes"] for entry in json.loads(
            (core.ROOT / "content/environments/procedural_architecture_v1/index.json").read_text()
        )["files"] if entry["file"] == "passages/return_gallery.glb"),
        "collision_meshes": len(collisions),
        "collision_vertex_coordinates_unchanged": True,
        "protected_mortar_vertices_unchanged": protected,
        "profile": {"spring_m": profile.spring, "rise_m": profile.crown - profile.spring,
                    "intrados_radius_m": profile.radius},
        "roof_stones": len(roofs),
        "roof_triangles": sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in roof),
        "operation": "Preserve the original collision and interior; round the exterior mortar and add stone roofing.",
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


def rock():
    core.empty_scene()
    bpy.ops.import_scene.gltf(filepath=str(OUT / "rock_lod0.glb"))
    source = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    source.data.transform(source.matrix_world)
    source.matrix_world = Matrix.Identity(4)
    layout = json.loads((core.ROOT / "content/environments/procedural_bridge_v1/layout.json").read_text())
    cutters = []
    for room in layout["rooms"]:
        plan = [architecture.flat(point) for point in room["points"]]
        centre = sum(plan, Vector((0, 0))) / len(plan)
        polygon = [point + (point - centre).normalized() * 0.9 for point in plan]
        cutters.append(prism("RoomClearance", polygon, room["floor"] - 0.3, room["floor"] + room["height"] + 0.8))
    for route in layout["routes"]:
        for p, q in zip(route["points"], route["points"][1:]):
            a, b = core.to_blender(p), core.to_blender(q)
            axis = b - a
            axis.z = 0
            axis.normalize()
            side = axis.cross(Vector((0, 0, 1))) * (route["width"] * 0.5 + 0.9)
            front, back = a - axis * 0.8, b + axis * 0.8
            polygon = [(point.x, point.y) for point in [front - side, back - side, back + side, front + side]]
            cutters.append(prism("RouteClearance", polygon, min(a.z, b.z) - 0.3, max(a.z, b.z) + 4.5))
    rocks = []
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
        "boundary_edges": 0,
        "nonmanifold_edges": 0,
        "triangles": sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in rocks),
        "collision": "none; existing shaft collision is retained",
        "clearance": "Visual mesh carved outside room volumes and route ribbons with 0.9m lateral margin.",
    }
    (OUT / "rock-placement.json").write_text(json.dumps(report, indent=2) + "\n")
    print("ROCK_CLIFF_BUILT", json.dumps(report), flush=True)


if __name__ == "__main__":
    gallery()
    rock()
