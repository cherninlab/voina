# Procedural generators

Repeated construction in SECHA's environments is made by Blender scripts, not placed by hand: bridges, rubble, hanging cloth and floors. Each generator is a reproducible command that reads real level data, can run physics, bakes the result and exports a GLB that Godot loads. Image-to-3D tools (CL3D) are reserved for unique, chunky shapes, which a generator may consume as optional parts.

## The loop

1. Export the level: `godot --headless --path . -s scripts/art/export_dungeon_layout.gd -- --out=/abs/layout.json`. This writes routes, mitered ribbon edges, supports, rooms and outlines in Godot coordinates.
2. Run the generator headless and pinned to Blender 5.2: `blender --factory-startup -b --python-exit-code 1 --python scripts/art/<generator>.py -- <layout.json> <out dir>`. Always pass `--factory-startup`, because user add-ons change results.
3. Simulate where it helps, then bake:
   - rigid bodies for rubble
   - cloth for banners and cobwebs
   - exact catenary maths, not simulation, for ropes and chains
   - Cycles AO into vertex colour R
4. Export a GLB plus a JSON report: seed, inputs, metrics, sha256, and repo-relative paths only.
5. Import in Godot (`--headless --editor --quit`) and run a contract test against the real collision and layout.
6. Capture same-camera before/after frames with `scripts/godot_bg.sh` and inspect them before shipping.

## Shared toolkit: `scripts/art/procgen/`

| Module | Purpose |
| --- | --- |
| `core` | arguments after `--`, Blender version pin, empty metric scene, `rng(seed, *keys)` streams, `to_blender` / `to_godot`, reports |
| `shapes` | `Builder` (one mesh per material, UVs, a `Color` attribute); `prism`, `timber`, `plank`, `bar`, with optional miter `start_cut` / `end_cut` planes |
| `curves` | `catenary(a, b, slack)`, `sag`, `tube` (rope), `chain` (interlocking links) |
| `bake` | `ao_to_color(objects)`: AO into Color.R, keeping G and B |
| `export` | `glb(objects, path)` with COLOR_0 and TEXCOORD_0; `collision_copy(obj, 'colonly' or 'convcolonly')` |

`selftest.py` exercises every module and round-trips a GLB. A generator task may add its own module (`rigid.py`, `cloth.py`, `tiles.py`); changes to shared modules go through a note on T-159.

### Colour channels

- **R:** baked AO.
- **G:** per-piece variation.
- **B:** edge wear.

The dungeon surface shader multiplies albedo by `COLOR.rgb`, so a generator that uses that material should write neutral G and B, or `(AO, AO, AO)`. UV-mapped generators can bring their own small shader in their content folder, as the bridge does.

## Why bake

- **Shadows:** Godot's Mobile renderer has no SSAO, so contact shading between boards and bearers or stones and floors must live in the mesh.
- **Physics:** simulation runs once in Blender, never at runtime.
- **Reproducibility:** generators are deterministic for a seed. Every output records its seed, its inputs and its hash, so another agent can rebuild or extend it.

## Generators

| Task | Generator | Output |
| --- | --- | --- |
| T-159 | `build_procedural_bridge.py` | `content/environments/procedural_bridge_v1/` wooden bridges fitted to `high_span` and `low_span` |
| T-163 | `build_rubble.py` | `content/environments/procedural_rubble_v1/` physics-settled rubble piles |
| T-164 | `build_hanging.py` | `content/environments/procedural_hanging_v1/` banners, drapes, cobwebs, ropes |
| T-165 | `build_flagstones.py` | `content/environments/procedural_flagstone_v1/` seamless floor modules |
| T-166, T-167 | CL3D | chunky bridge furniture and rubble sources that the generators can consume |

CL3D is a local build of Tencent Hunyuan3D-2mini. Record its outputs under the Tencent Hunyuan 3D 2.0 Community License, which does not apply in the EU, UK or South Korea. Using its outputs in a release is the owner's decision (T-118).
