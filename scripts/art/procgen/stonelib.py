"""A library of unique stones to build whole structures from.

Sculpting every stone of a dungeon (tens of thousands) one by one is too slow,
so a generator makes a few hundred truly unique stones per kind, spread over
face proportions (square to long), and fits one to each slot: the stone with
the nearest proportion, scaled to the slot (never more than ~20% out of its
own shape), turned, flipped and given its own tone. Neighbours never share a
stone, and no two placements look alike.

    lib = stonelib.Library(rng, 'squared_rubble', count=240)
    obj = lib.place(rng, length=0.46, height=0.24, depth=0.3, name='S1')   # face +y? no: see below

Placed stones use wall-local axes: x along the wall, y up, z out of the face
(front at z = 0). Library meshes are stored once and linked, so memory and
build time stay small; `bake` merges them per chunk.
"""
import math

import bpy
from mathutils import Matrix, Vector

from . import core, stones


class Library:
    def __init__(self, rng, kind: str, count: int = 240, triangles: int = 900, aspects=(0.8, 3.2), name: str = None,
                 hidden_back: float = None):
        """`hidden_back`: drop faces deeper than this behind the stone's front
        (metres at library scale), for stones whose backs sit inside a wall
        core and are never seen."""
        self.kind = kind
        self.entries = []  # (aspect, mesh, size: Vector(length, height, depth))
        collection = bpy.data.collections.new(f'StoneLibrary_{kind}')
        bpy.context.scene.collection.children.link(collection)
        collection.hide_render = True
        collection.hide_viewport = True
        low, high = aspects
        for index in range(count):
            # Log-spread proportions: as many squarish stones as long ones.
            aspect = math.exp(math.log(low) + (math.log(high) - math.log(low)) * (index + rng.random()) / count)
            height = 0.25
            size = (height * aspect, rng.uniform(0.26, 0.36), height)
            obj = stones.make(kind, rng, size, name=f'{name or kind}_lib_{index}', triangles=triangles)
            # Library axes: x along, y up, z out of the face; front at z = 0.
            obj.data.transform(Matrix.Rotation(math.radians(-90), 4, 'X'))
            mesh = obj.data
            xs = [v.co.x for v in mesh.vertices]
            ys = [v.co.y for v in mesh.vertices]
            zs = [v.co.z for v in mesh.vertices]
            # Fit by the body a few centimetres behind the front, not the bounding
            # box: the worn arrises then round over into tight joints instead of
            # leaving every stone floating in a wide bed of mortar.
            front = max(zs)
            body = [v.co for v in mesh.vertices if front - 0.11 < v.co.z < front - 0.035]
            bx = [c.x for c in body] or xs
            by = [c.y for c in body] or ys
            if max(bx) - min(bx) < 0.5 * (max(xs) - min(xs)) or max(by) - min(by) < 0.5 * (max(ys) - min(ys)):
                # Too few vertices in the band (a very light stone): fit by the bounding box.
                bx, by = xs, ys
            mesh.transform(Matrix.Translation((-(max(bx) + min(bx)) * 0.5, -(max(by) + min(by)) * 0.5, -front)))
            dims = Vector((max(bx) - min(bx), max(by) - min(by), front - min(zs)))
            if hidden_back is not None:
                import bmesh
                bm = bmesh.new()
                bm.from_mesh(mesh)
                bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < -hidden_back], context='FACES')
                bm.to_mesh(mesh)
                bm.free()
            self.entries.append(((dims.x / dims.y), mesh, dims))
            bpy.context.scene.collection.objects.unlink(obj)
            collection.objects.link(obj)
        self.entries.sort(key=lambda e: e[0])
        self.used = {}

    def pick(self, rng, aspect: float, spread: int = 6):
        """One of the `spread` stones nearest in proportion, preferring the
        least used, so repeats are rare and never adjacent by construction."""
        nearest = sorted(self.entries, key=lambda e: abs(math.log(e[0] / aspect)))[:spread]
        nearest.sort(key=lambda e: self.used.get(e[1].name, 0) + rng.random() * 0.9)
        chosen = nearest[0]
        self.used[chosen[1].name] = self.used.get(chosen[1].name, 0) + 1
        return chosen

    def place(self, rng, length: float, height: float, depth: float, name: str, collection=None) -> bpy.types.Object:
        """A stone object filling a length x height face slot (wall-local
        axes, centred on x/y, front at z = 0) and `depth` deep."""
        aspect, mesh, dims = self.pick(rng, max(length, 0.02) / max(height, 0.02))
        obj = bpy.data.objects.new(name, mesh)
        flip_x = -1.0 if rng.random() < 0.5 else 1.0
        flip_y = -1.0 if rng.random() < 0.3 else 1.0
        obj.matrix_world = Matrix.Diagonal((flip_x * length / dims.x, flip_y * height / dims.y, depth / dims.z, 1.0))
        # Stones from different beds and different weathering: most mid, a few
        # dark, a few pale (the paintovers' walls are anything but uniform).
        obj['tone'] = rng.triangular(0.5, 1.2, 0.86)
        (collection or bpy.context.scene.collection).objects.link(obj)
        return obj
