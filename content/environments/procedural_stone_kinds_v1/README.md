# Procedural stone kinds v1 (T-182)

Six new stone kinds for the masonry engine, built in Blender 5.2 by
`scripts/art/procgen/stonekinds.py`. They are made to sit with the current
`squared_rubble` walls: the same convex cut core, the same arris wear, the same
broad lumps and pitch, fresh chips, and the same limestone face texture (T-180).
Each kind is still easy to tell apart by its size, outline, face and coursing.
Every stone is unique and built from a seed. None is a scaled copy of another.

![contact sheet](review/contact_sheet.png)

## Kinds and where to use them

Natural sizes are given as height up the face × length × depth behind the face.

| kind | natural size | triangles | look | use |
| --- | --- | --- | --- | --- |
| `dressed_ashlar` | 24-40 cm × 1.1-3× height × 24-36 cm | 280 | near-rectangular with crisp but unevenly worn arrises; 1.6-2.4 cm front chamfers that form V-joints; broad batter strokes on the face; 3-7 mm joints | **walls** of dressed rooms; **pier and pilaster** faces; jambs and springers of **arches** |
| `thin_slab` | 6-12 cm × 3-10× height × 18-30 cm | 200 | long, flat bedded stones with split, stepped faces, broken oblique ends and slightly wavy beds | coursed **walls** between dressed dressings; wall backs; low walls; the bands between ashlar courses |
| `small_squared` | 8.5-12 cm × 1.6-2.8× height (about 22 cm) × 10-15 cm (brick-sized) | 150 | roughly squared small units with a slightly pillowed hammer-dressed face | **vault webs**; brick-style **arch** rings and relieving arches; small piers; infill panels |
| `big_quoin` | 30-55 cm × 60-120 cm × 35-60 cm | 320 | heavy blocks with 2.5-3.8 cm chamfers and a flat drafted margin (4.5-6.5 cm) around a rock-faced boss standing 2.8-4.5 cm proud | **piers** (bases and shafts); **plinths**; quoins at wall corners; springer blocks under **arches** |
| `galleted_rubble` | 14-34 cm × 0.8-2.4× height × 20-34 cm | 220 | irregular split rubble with polygonal outlines and convex weathered faces, laid roughly to courses, with small spalls pressed into the wider joints | rough **walls**: cellars, tunnels, wall cores exposed by ruin |
| `floor_flag` | 30-62 cm wide × 1-2.2× width × 6-10 cm thick | 360 | flat paving slabs with chipped edges, broken corners, worn round top arrises and a shallow foot-worn hollow (5-10 mm) | **floors** of rooms and passages; landings; thresholds |
| spalls (`spall()`) | 2.5-6.5 cm long | 70 | sharp, fresh flakes | galleting in `galleted_rubble` joints, or packing anywhere a joint is wide |

`squared_rubble` (stones.py) stays the default walling stone. The mixed panel
on the contact sheet (bottom right) puts a quoin plinth, squared rubble, an
ashlar band and thin slabs into one wall, to show that the kinds work together.

## API

```python
from procgen import stonekinds, masonry

stone = stonekinds.make('dressed_ashlar', rng, size=(0.62, 0.30, 0.32), name='A1')  # like stones.make
size = stonekinds.natural_size('thin_slab', rng)            # a size in the kind's own range
pin = stonekinds.spall(rng, name='G1')                       # one galleting spall
lib = stonekinds.Library(rng, 'big_quoin', count=40)         # like stonelib.Library
parts = masonry.Wall(4.0, 2.0, 0.9, **stonekinds.KINDS['big_quoin']['wall']).build(lib, rng)
parts += stonekinds.gallet(parts, rng)                       # spalls into a built wall's open joints
```

- **`make(kind, rng, size, name, triangles=None)`** has the same contract as
  `stones.make`:
  - `size = (x along the face, y depth behind the front, z up the face)` in metres;
  - centred at the origin, with the front (show) face on local **-y**;
  - a `Color` corner attribute: R = 1 (AO later), G = per-stone tone, B = 1 on fresh breaks;
  - a box-projected `UVMap` in local metres;
  - smooth shading, with sharp edges from the kind's angle.

  `triangles=None` uses the kind's budget. Any `stones.LOOKS` kind
  (`squared_rubble`, `ashlar`, ...) is passed through to `stones.make`.
- **Floor flags use the same axes.** The walking face is the front (-y), y is the
  thickness, and z is the width in plan. Lay a floor with `masonry.Wall` and
  `masonry.place(parts, origin, along, up=<a plan direction>)`, so that the
  wall's "out of the face" axis points up, as the review does.
- **`KINDS[kind]`** holds the look parameters, the natural `height`, `aspects`
  (length / height), `depth` and, for quoins, `length` ranges, the triangle budget, a `use` string, and
  `wall`, the `masonry.Wall` settings (course heights, stone lengths, joints,
  proud) the review lays each kind with.
- **`obj['boss']`**: for `big_quoin`, how far the rock-faced boss stands proud of
  the drafted margin, in metres. It is 0 for the other kinds.
- **`Library(rng, kind, count, triangles=None, name=None, hidden_back=None, heights=None, aspects=None, tone=(0.72, 1.18))`**
  builds unique stones at the kind's natural size and picks them by proportion
  **and height**. `place(rng, length, height, depth, name, collection=None)`
  has stonelib's contract, so it can be passed to `masonry.Wall.build` as `lib`
  or `quoins`. Its axes are x along, y up and z out of the face, with the front
  at z = 0.

## Integrating with `stonelib.Library` (T-177)

- **Don't pass these kinds to `stonelib.Library`; use `stonekinds.Library`.**
  `stonelib.Library` would fail on the new kinds, because it calls `stones.make`
  and `stones.LOOKS[kind]` raises a KeyError. It also builds every stone 0.25 m
  tall. Fitting such a stone to a 7 cm slab course, or to a 1 m quoin, would
  stretch it 3-4× out of shape.
- **`place` keeps each stone's own depth proportion.** It uses `depth` only within
  -20/+25 % of the face scale, so arrises keep their shape. It does not stretch
  every stone to 24-36 cm like stonelib. Every walling kind is at least 10 cm
  deep, so stones still reach the mortar core (recess 3.4 cm).
- **Quoins are fitted by their face plane.** For `big_quoin`, z = 0 is the drafted
  margin, so the boss stands up to 4.5 cm proud of the wall line. Leave room for
  this wherever quoins meet a flush face.
- **`tone` is a plain uniform 0.72-1.18 by default.** T-177's working copy of
  stonelib moves to a triangular spread (0.5-1.2, mode 0.86). Pass `tone=...`
  to match whatever lands.
- **Arch rings.** `masonry.ring` / `stones.voussoir` cut true radial voussoirs.
  These kinds are rectangular. A brick-style ring of `small_squared` units, or
  dressed voussoirs from `dressed_ashlar`, needs a ring builder that asks
  `Library.place` for radial slots. That belongs in masonry.py (T-177's scope)
  and is not built here.
- **`gallet(parts, rng)` works in wall-local space.** Call it after
  `Wall.build` and before `masonry.place`. It ignores the mortar core
  (tone < 0) and only fills gaps deeper than 4 cm behind the face, at least
  2.2 cm wide and 11 cm apart.

## Construction, in brief

1. **Convex core.** A box is cut by six jittered planes (`stones._cut`,
   `stones._tilt`). Then come the kind's chamfers on the front arrises and small
   arrises on the rest, splitting planes, broken slab ends and corner breaks.
2. **Dense surface.** The core is voxel remeshed (3.6-9.5 mm by kind). Laplacian
   wear rounds the arrises, and is patchy, so some stretches stay crisp. Slabs
   bend and swell along their length (wavy beds), and flags wear far more on top.
3. **Kind relief.**
   - ashlar: planar batter strokes;
   - quoin: the drafted margin and the boss of pitched, dished scars;
   - flags: the wear hollow;
   - slabs, small squared and rubble: split facets, from the lower envelope of
     tilted dishes on Voronoi cells, stretched along the bedding for slabs;
   - rubble and small squared: convex pillowed faces.
4. **Family relief.** The stones.py layers come next: broad lumps, distorted-noise
   pitch and grain.
5. **Fresh chips.** Conchoidal scallops (spherical cuts) on the front arrises are
   marked fresh.
6. **Decimation.** A collapse decimate brings each stone to its budget. A vertex
   group keeps triangles on the face and arrises rather than the hidden back.

Everything is driven by the rng that is passed in. The same seed rebuilds the
same stones in any Blender 5.2 process. `mathutils.noise.noise_vector` is
avoided, because it returns different values in each process.

## Review (`review/`, Cycles, Metal, 96 samples)

- `contact_sheet.png`: one 2.5 × 1.8 m panel per kind, laid course by course with
  `masonry.Wall`, plus the floor-flag patch and the mixed wall. The
  `squared_rubble` panel, top left, is built exactly as build_architecture.py
  builds its walls, as the reference.
- `closeups.png`: about 0.75 m of each panel under the raking torch.
- `lineup.png`: single stones of each kind at natural size, with spalls beside
  the galleted rubble.

Shading copies `build_stone_surface.review_material` (T-180's stand-in for
`dungeon_surface.gdshader`):

- the stones use the `procedural_stone_surface_v1/limestone/` albedo, normal_gl,
  roughness and AO maps;
- each stone face is box-projected in world metres at `surface()` density 0.555,
  with a random offset per stone;
- each stone is multiplied by its tone and brightened 8 % on fresh breaks, as
  the game's vertex colour does;
- the mortar core uses the same maps, darkened.

Each panel is lit by a warm point torch from the upper left and a dim, cool
area fill from behind the camera. `stone_kinds.json` records the triangle
counts, library sizes, seed, device and image hashes.

Rebuild everything (about 2.5 minutes on an M-series Mac):

```
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_stone_kinds_review.py -- --samples 96
```

Other options:

- `--quick`: small libraries and small renders;
- `--only kind,kind`: only those panels (plus the reference);
- `--no-sheet`: the lineup only;
- `--dump DIR`: write every view on its own;
- `--out DIR`: write somewhere else.

## Known limits

- **Batter tooling is broad.** A 120-320 triangle budget cannot keep fine tool
  marks. Ashlar faces keep only broad batter strokes (7.5-10 cm wide, 3 mm deep),
  as planar facets that the decimator can hold. The limestone texture supplies
  the fine dressing. Under a frontal light the faces of ashlar and squared
  rubble look much alike up close. The difference is in the outline, the
  chamfers and the joints.
- **The bosses are soft.** They read as a framed, rough dome rather than a
  sharply pitched rock face, because sharper scars broke up into crumpled
  slivers at 320 triangles. The lower pitch line casts a thin shadow line above
  the margin, which is correct but can read as a hairline at a distance.
- **Rubble faces can dip behind the mortar.** A few galleted-rubble stones dip
  behind the 3.4 cm mortar recess near their edges, so mortar shows in pockets
  inside their outline.
- **Spall placement is regular.** Spalls follow the open joints at a fixed
  minimum spacing, so on a large wall they can look evenly spaced.

## Provenance and licence

Procedural from Blender, so CC0 by construction. No scans, external images,
HDRIs, node assets or AI-generated pixels are read. The only image input is the
CC0 procedural limestone set from T-180. Seed **182**.
