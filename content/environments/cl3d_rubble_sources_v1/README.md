# CL3D rubble sources v1 — T-167

Eighteen distinct image-to-3D chunks: six broken ashlar stones, six rough rocks, three broken column drums and three joined brick clumps. Each has three closed LODs, at most **1,500 / 600 / 200 triangles**, plus source images, prompts, provenance and review evidence. These are source meshes for physics/rubble generation; no room placement is made by this task.

## Use the assets

`manifest.json` is the handoff index. Its `assets` array contains each id, kind, relative GLB paths, dimensions in Godot XYZ metres, exact source-image/raw/LOD hashes, model seed/timing, origin, cleanup and material hint. Each model is centred on its own bounding box, Y up, with transforms baked at uniform scale. The longest dimensions range from approximately 0.22 to 0.75 m.

- `sources/<id>_lod0.glb`, `_lod1.glb`, `_lod2.glb`: explicit separate LOD files. The GLBs embed neutral review clay, metre-space box UVs and smooth/sharp normals.
- `references/`: original ImageGen conditioning references and exact receipts. `prompts/` preserves every sent prompt; second-pass ashlar01/04/06 references removed unwanted mortar/course patterns. Rejected first passes are kept in `references/rejected/`.
- `conditioning/`: masked RGBA inputs. This is an internal model-preparation step, not a creative edit; original generated reference bytes remain unchanged.
- `raw_cl3d/`: original high-poly reconstruction GLBs and runner reports. Raw inputs/reference/review directories are excluded from Godot import with `.gdignore`.
- `review/`: actual Blender front/back renders, native Godot clay views, material previews and verification logs. Contact sheets show all eighteen source shapes.

These are closed visual meshes for a consumer to turn into convex rigid-body hulls. They contain no runtime physics bodies or collision shapes. A convex hull will fill concavities (especially the L-like ashlar06 and arched brick02); use a compound hull if that gap matters. Never non-uniformly scale a physics body.

T-163 and T-179 can use the chunks in future rubble bakes. The current `scripts/art/build_rubble.py` still uses procedural sources and has no implemented CL3D manifest loader, so consuming this index requires its owner's scoped change; this task does not claim automatic integration.

## Materials supplied alongside them

Each manifest entry gives a `material_hint` into the complementary **T-183** library: `../stone_brick_materials_v1/`. It contains nine face materials, each with albedo, OpenGL normal, roughness, 16-bit height and AO. Use its `surface.tres` preset to get coherent varied sampling; using the PNGs with plain repeat reintroduces the user-rejected tiling.

Actual native previews under `review/godot_textured/` apply these material resources to the imported mesh. They are an optional material trial, while each GLB itself retains neutral clay. Brick/mortar material boundaries are not segmented or UV-painted by CL3D; the brick-clump preview applies a single material to the full chunk. Distinct mortar material assignment is a later asset-finishing step.

For these UV-equipped chunks, duplicate the hinted material and apply `material_parameters` from the manifest: mapped UVs, density 2 repeats/m for stone or 4 repeats/m for clay, normal strength 0.65, parallax disabled. The finer density avoids enlarged texels on close views of small fragments. The original world-projected trial stretched curved faces; the final previews use supplied metre UVs and verified import-generated tangents. Height is still supplied in the material library for larger surfaces or a later relief tuning pass. The base presets retain their wall-oriented defaults for other geometry. Recommended density/relief and all map hashes are in the material library's `materials.json`.

## Generation and verification

The latest direct user request (“fix it and generate more things using CL3D”) authorized this additional batch. We made isolated ImageGen references first, extracted their foregrounds, then ran the local CL3D/2mini runner with the recorded deterministic seeds, 50 steps and octree 384 on MPS float16. A separate approval of final in-dungeon appearance is not inferred from the generation request.

`prepare_sources.py` reuses the project's connected-island cleanup, export, review and box-UV helpers. It retains the largest connected mass, recalculates normals, applies uniform size, centres the bounds and decimates successively. Voxel repair is used only if an actual open/nonmanifold edge remains; the manifest records whether it was needed. Every LOD is checked for boundary/nonmanifold edges and triangle budget before export.

`review/mesh-audit.json` independently reopens exported GLBs, welds only duplicated positions at UV/normal seams, and verifies closed, consistently wound positive-volume geometry, exact bounding-box centre, finite vertices, budgets and hashes. The position weld is necessary for a geometric closure test because glTF splits vertices at UV/sharp-normal discontinuities; it does not repair or alter delivered files.

`preview_sources.gd` imports all 54 LODs, checks actual triangle counts, bounds/origin and absence of unexpected collision, then captures all eighteen source models both in clay and with the material hint applied. Windowed runs go through `scripts/godot_bg.sh`. Engine/import/smoke and visual review results are recorded in `review/verification.json` after completion. No dungeon traversal, final human visual approval or scene-scale performance is claimed.

## Reproduce

From the repository root, with the already configured local CL3D environment:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python content/environments/cl3d_rubble_sources_v1/generate_sources.py
blender --factory-startup -b -t 4 --python-exit-code 1 --python content/environments/cl3d_rubble_sources_v1/prepare_sources.py
"$GODOT" --headless --editor --path . --quit
GODOT="$GODOT" scripts/godot_bg.sh --path . --resolution 1280x720 --script res://content/environments/cl3d_rubble_sources_v1/preview_sources.gd
python3 scripts/smoke_test.py "$GODOT"
```

`prepare_sources.py -- <id>` permits a scoped rerun. The generator refuses to silently reuse an existing raw output if its masked input hash differs. The shared external runner skips existing outputs; preserve raw results or use a new versioned output directory for intentional model/seed changes.

## Provenance

Concept images: built-in ImageGen, exact prompts and unmodified originals/receipts retained. Shape inference: **CL3D is a local build of Tencent Hunyuan3D-2mini**, recorded under the Tencent Hunyuan 3D 2.0 Community License, per `docs/procedural-generators.md` and T-166/T-167. Repository policy records that the licence does not apply in the EU, UK or South Korea; release use is the owner's decision under T-118.

`model-provenance.json` records the checkpoint/config/pipeline/foreground/runner hashes and the installed foreground extractor identity. The current local `models/LICENSE` is a short CL3D branding statement, so it is not substituted for the upstream model identity/licence record. These AI-assisted meshes are not labelled CC0-by-construction procedural assets. No external scan/texture download was added.
