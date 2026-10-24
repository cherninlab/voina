"""Semi-solid ground: a fine heightfield that objects press into under their
own weight or a blow, with the displaced soil heaped into a rim around them.
Also cart ruts and digging. Use it to seat column bases, posts, boulders and
rubble so they sit *in* the ground instead of on it.

    ground = soil.Ground(size=(4, 4), centre=(0, 0), cell=0.02, rng=rng)
    ground.press(column, soil.SOILS['packed road'])          # weight only
    ground.press(stake, soil.SOILS['garden'], blows=3)       # hammered in
    ground.rut([(x0, y0), (x1, y1)], width=0.12, depth=0.05)
    ground.dig((x, y), radius=0.4, depth=0.3)
    obj = ground.mesh('Soil')                                 # Builder-style mesh

Sinking follows a plate-bearing model: pressure = weight / footprint area,
depth = pressure / k (k is the soil's modulus of subgrade reaction, N/m^3),
plus energy from blows spread over the footprint. The object moves down by
that depth; ground under it takes the shape of its underside; `heave` of the
displaced volume (the rest is compaction) rises in a ring beside it.
Blender units: metres, z up.
"""
import math

import bmesh
import bpy
import numpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import core

SOILS = {
    # k (N/m^3), heave share of displaced volume, rim width (m)
    'packed road': {'k': 4.0e6, 'heave': 0.35, 'rim': 0.10},
    'garden': {'k': 1.2e6, 'heave': 0.55, 'rim': 0.14},
    'mud': {'k': 2.5e5, 'heave': 0.8, 'rim': 0.2},
    'rubble fill': {'k': 8.0e6, 'heave': 0.2, 'rim': 0.08},
}


class Ground:
    def __init__(self, size=(4.0, 4.0), centre=(0.0, 0.0), cell: float = 0.02, base: float = 0.0, rng=None,
                 roughness: float = 0.004):
        self.cell = cell
        self.nx, self.ny = int(round(size[0] / cell)) + 1, int(round(size[1] / cell)) + 1
        self.x0, self.y0 = centre[0] - size[0] * 0.5, centre[1] - size[1] * 0.5
        self.height = numpy.full((self.nx, self.ny), base, dtype=numpy.float64)
        self.disturbed = numpy.zeros((self.nx, self.ny), dtype=numpy.float64)
        if rng is not None and roughness > 0:
            # Smooth lumps a few centimetres across, not per-cell noise.
            for _ in range(12):
                cx, cy = rng.uniform(0, self.nx), rng.uniform(0, self.ny)
                radius = rng.uniform(4, 18)
                amount = rng.uniform(-1, 1) * roughness
                self.height += amount * self._kernel(cx, cy, radius)

    def _kernel(self, cx: float, cy: float, radius: float):
        ix = numpy.arange(self.nx)[:, None]
        iy = numpy.arange(self.ny)[None, :]
        return numpy.exp(-((ix - cx) ** 2 + (iy - cy) ** 2) / (2 * radius ** 2))

    def xy(self, i, j):
        return self.x0 + i * self.cell, self.y0 + j * self.cell

    def at(self, x: float, y: float) -> float:
        i = min(max(int(round((x - self.x0) / self.cell)), 0), self.nx - 1)
        j = min(max(int(round((y - self.y0) / self.cell)), 0), self.ny - 1)
        return float(self.height[i, j])

    def underside(self, obj: bpy.types.Object):
        """Lowest point of `obj` above each ground cell it covers (nan elsewhere)."""
        verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
        tree = BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in obj.data.polygons])
        low = Vector(tuple(min(v[k] for v in verts) for k in range(3)))
        high = Vector(tuple(max(v[k] for v in verts) for k in range(3)))
        i0, i1 = max(0, int((low.x - self.x0) / self.cell)), min(self.nx - 1, int((high.x - self.x0) / self.cell) + 1)
        j0, j1 = max(0, int((low.y - self.y0) / self.cell)), min(self.ny - 1, int((high.y - self.y0) / self.cell) + 1)
        under = numpy.full((self.nx, self.ny), numpy.nan)
        for i in range(i0, i1 + 1):
            for j in range(j0, j1 + 1):
                x, y = self.xy(i, j)
                hit = tree.ray_cast(Vector((x, y, low.z - 1.0)), Vector((0, 0, 1)), high.z - low.z + 2.0)
                if hit[0] is not None:
                    under[i, j] = hit[0].z
        return under

    def press(self, obj: bpy.types.Object, soil: dict, mass: float = None, blows: int = 0, blow_energy: float = 300.0,
              max_depth: float = 0.25) -> dict:
        """Sink `obj` into the ground by weight (and `blows` hammer blows of
        `blow_energy` joules) and reshape the soil around it."""
        if mass is None:
            mass = obj.rigid_body.mass if obj.rigid_body else 1.0
        under = self.underside(obj)
        # Seat the object on the highest ground under it first.
        lift = float(numpy.nanmax(numpy.where(numpy.isnan(under), numpy.nan, self.height - under))) if numpy.any(~numpy.isnan(under)) else 0.0
        footprint = ~numpy.isnan(under) & (under + lift - self.height <= self.cell * 1.5)
        area = max(float(footprint.sum()) * self.cell ** 2, self.cell ** 2)
        pressure = mass * 9.81 / area
        depth = pressure / soil['k']
        if blows:
            # Work done by blows: E = integral of k * A * z dz  ->  z = sqrt(2E / (kA)).
            depth = math.sqrt(depth ** 2 + 2.0 * blows * blow_energy / (soil['k'] * area))
        depth = min(depth, max_depth)
        drop = depth - lift
        obj.location.z -= drop
        bpy.context.view_layer.update()
        under = self.underside(obj)
        cover = ~numpy.isnan(under) & (self.height > under)
        removed = float(numpy.sum((self.height - under)[cover])) * self.cell ** 2
        self.height[cover] = under[cover]
        self.disturbed[cover] = 1.0
        heaped = self._heave(cover, removed * soil['heave'], soil['rim'])
        return {'depth_m': round(depth, 4), 'drop_m': round(drop, 4), 'footprint_m2': round(area, 4),
                'pressure_kpa': round(pressure / 1000, 2), 'removed_m3': round(removed, 6), 'heaped_m3': round(heaped, 6)}

    def _heave(self, cover, volume: float, rim: float) -> float:
        """Raise a ring beside `cover` holding `volume`, peaking just outside it."""
        if volume <= 0 or not cover.any():
            return 0.0
        weights = self._ring_weights(cover, rim)
        total = float(weights.sum()) * self.cell ** 2
        if total <= 0:
            return 0.0
        self.height += weights * (volume / total)
        self.disturbed = numpy.maximum(self.disturbed, numpy.clip(weights * 1.5, 0, 1))
        return volume

    def _ring_weights(self, cover, rim: float):
        # Distance (cells) from the footprint by repeated dilation: no scipy needed.
        distance = numpy.where(cover, 0.0, numpy.inf)
        steps = int(math.ceil(rim * 2.5 / self.cell))
        frontier = cover.copy()
        for step in range(1, steps + 1):
            grown = frontier.copy()
            grown[1:, :] |= frontier[:-1, :]
            grown[:-1, :] |= frontier[1:, :]
            grown[:, 1:] |= frontier[:, :-1]
            grown[:, :-1] |= frontier[:, 1:]
            new = grown & ~frontier
            distance[new] = step
            frontier = grown
        d = distance * self.cell
        # A lip right at the edge that falls off over the rim width.
        weights = numpy.where((d > 0) & numpy.isfinite(d), numpy.exp(-((d - rim * 0.35) / (rim * 0.6)) ** 2), 0.0)
        return weights

    def rut(self, path, width: float, depth: float, soil: dict = None) -> float:
        """A wheel or drag track along `path` [(x, y), ...] with a soft lip."""
        soil = soil or SOILS['packed road']
        cover = numpy.zeros((self.nx, self.ny), dtype=bool)
        sink = numpy.zeros((self.nx, self.ny))
        ix = numpy.arange(self.nx)[:, None] * self.cell + self.x0
        iy = numpy.arange(self.ny)[None, :] * self.cell + self.y0
        for (ax, ay), (bx, by) in zip(path, path[1:]):
            dx, dy = bx - ax, by - ay
            length2 = max(dx * dx + dy * dy, 1e-9)
            t = numpy.clip(((ix - ax) * dx + (iy - ay) * dy) / length2, 0, 1)
            dist = numpy.hypot(ix - (ax + t * dx), iy - (ay + t * dy))
            profile = numpy.clip(1 - (dist / (width * 0.5)) ** 2, 0, None) * depth
            sink = numpy.maximum(sink, profile)
        cover = sink > 0
        removed = float(sink.sum()) * self.cell ** 2
        self.height -= sink
        self.disturbed[cover] = 1.0
        return self._heave(cover, removed * soil['heave'], soil['rim'])

    def dig(self, centre, radius: float, depth: float, soil: dict = None, spoil_side=(1.0, 0.0)) -> float:
        """A bowl-shaped hole with its spoil heaped on one side."""
        soil = soil or SOILS['garden']
        ix = numpy.arange(self.nx)[:, None] * self.cell + self.x0
        iy = numpy.arange(self.ny)[None, :] * self.cell + self.y0
        dist = numpy.hypot(ix - centre[0], iy - centre[1])
        sink = numpy.clip(1 - (dist / radius) ** 2, 0, None) * depth
        removed = float(sink.sum()) * self.cell ** 2
        self.height -= sink
        self.disturbed[sink > 0] = 1.0
        side = Vector(spoil_side).normalized()
        heap = numpy.exp(-(((ix - centre[0] - side.x * radius * 1.8) ** 2 + (iy - centre[1] - side.y * radius * 1.8) ** 2) / (2 * (radius * 0.7) ** 2)))
        heap *= removed * 1.15 / max(float(heap.sum()) * self.cell ** 2, 1e-9)  # loosened spoil bulks up
        self.height += heap
        self.disturbed[heap > depth * 0.05] = 1.0
        return removed

    def mesh(self, name: str = 'Soil') -> bpy.types.Object:
        """Grid mesh: UVs in metres, Color R = 1 (bake AO later), G = height
        variation, B = disturbed soil (fresh, darker or looser in shaders)."""
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new('UVMap')
        color = bm.loops.layers.float_color.new('Color')
        verts = [[bm.verts.new((*self.xy(i, j), float(self.height[i, j]))) for j in range(self.ny)] for i in range(self.nx)]
        spread = max(float(numpy.ptp(self.height)), 1e-6)
        low = float(self.height.min())
        for i in range(self.nx - 1):
            for j in range(self.ny - 1):
                quad = [verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]]
                face = bm.faces.new(quad)
                for loop, (a, b) in zip(face.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                    x, y = self.xy(a, b)
                    loop[uv].uv = (x, y)
                    loop[color] = (1.0, (float(self.height[a, b]) - low) / spread, float(self.disturbed[a, b]), 1.0)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.shade_smooth()
        mesh.color_attributes.active_color = mesh.color_attributes['Color']
        return core.link(bpy.data.objects.new(name, mesh))

    def volume(self) -> float:
        return float(self.height.sum()) * self.cell ** 2
