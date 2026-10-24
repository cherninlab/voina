"""Build a continuous, chamfered masonry shaft. Stdlib only, native Godot axes.

python3 scripts/art/build_dungeon_masonry.py
Original procedural geometry; no external assets or simulation dependencies.
"""
from collections import Counter
from math import sqrt
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "content/environments/dungeon_masonry_v1/pier.obj"
# Chamfered shoulders and a shallow central rebate break the front silhouette.
PROFILE = [(-.5, -.38), (-.38, -.5), (.38, -.5), (.5, -.38),
           (.5, .28), (.35, .48), (.17, .5), (.12, .40),
           (-.12, .40), (-.17, .5), (-.35, .48), (-.5, .28)]
RINGS = [(-.5, 1), (-.46, 1), (-.40, .94), (-.12, .91),
         (.22, .86), (.43, .87), (.5, .94)]
vertices = [(x * width, y, z) for y, width in RINGS for x, z in PROFILE]
faces = []
n = len(PROFILE)
for ring in range(len(RINGS) - 1):
    for corner in range(n):
        a, b = ring * n + corner, ring * n + (corner + 1) % n
        faces.append((a, a + n, b + n, b))
for ring, top in [(0, False), (len(RINGS) - 1, True)]:
    center = len(vertices)
    vertices.append((0, RINGS[ring][0], 0))
    for corner in range(n):
        a, b = ring * n + corner, ring * n + (corner + 1) % n
        faces.append((center, b, a) if top else (center, a, b))
lines = ["# Original continuous masonry shaft, metre-unit normalized bounds", "o MasonryPier"]
lines += ["v %.8f %.8f %.8f" % vertex for vertex in vertices]
normals = []
for face in faces:
    a, b, c = [vertices[i] for i in face[:3]]
    u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
    normal = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
    length = sqrt(sum(value * value for value in normal))
    assert length > 0
    normals.append(tuple(value / length for value in normal))
lines += ["vn %.8f %.8f %.8f" % normal for normal in normals]
lines += ["f " + " ".join(f"{vertex+1}//{i+1}" for vertex in face) for i, face in enumerate(faces)]
OUT.write_text("\n".join(lines) + "\n")
assert min(v[1] for v in vertices) == -.5 and max(v[1] for v in vertices) == .5
assert len(faces) == 96
edges = Counter(tuple(sorted((face[i], face[(i+1) % len(face)]))) for face in faces for i in range(len(face)))
assert all(count == 2 for count in edges.values()), "Shaft has an open or nonmanifold seam"
print(f"MASONRY_MESH_OK: {len(vertices)} vertices, {len(faces)} faces, closed continuous shaft -> {OUT}")
