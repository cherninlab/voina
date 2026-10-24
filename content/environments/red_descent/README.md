# Current integrated revision (2026-10-24)

The runtime now uses the CC0 PBR library in `../dungeon_pbr_v2/`, the selected Poly Haven fort entrance in `../dungeon_geometry_v2/`, and the locally generated varied mesh kit in `../generated_dungeon_kit_v1/`. Their own source records document provenance and original map bytes. The generated bitmap studies described below are earlier iterations and are not the current stone/wood PBR source.

The material pass combines albedo, normals, roughness, AO, shallow near-view height relief, exposed plaster substrate, dampness and algae. Geometry supplies wall profiles, recess depth, arch shapes, broken boundaries and varied support construction. The dungeon imposes Natural presentation while retaining the player's saved outdoor theme. `review/rerender_v2/kit-final/` contains the latest real Mobile/Metal captures; the ImageGen paintover in the generated kit's review folder remains a target image.

# Earlier generated material study

Original SECHA dungeon architecture and procedural dressing by the project. New texture bitmaps were generated with native OpenAI ImageGen on 2026-10-23; no stock or downloaded third-party textures were added by this pass.

Runtime maps: `stone_albedo.png`, `stone_normal.png`, `stone_roughness.png`, `wood_albedo.png`, `wood_normal.png`. All are the unmodified 1254 × 1254 native outputs. Albedo prompts requested flat unlit repeatable surfaces. Normal and roughness generations referenced the corresponding albedo alone. Runtime import enables mipmaps and identifies normals as normal maps. The supplied normal maps visually follow the stone joints and wood grain; exact registration and perfectly seamless tiling are not guaranteed.

`generation.json` records native source paths, exact prompt files and SHA-256 hashes. Original reference inputs were actual iteration-02 engine captures plus the project's selected `content/art_direction/dungeon/maps_v2/05-cutaway.png` concept. Normal and roughness images use only their generated albedo as the image reference. The render study used iteration-02 `02-central-wall.png` as primary and the selected cutaway as mood/material reference. Its geometry drift is not authoritative for the level layout.

`review/.gdignore` excludes the review folder from Godot import/export. `review/iteration-02/` preserves the first complete in-engine geometry before materials; `review/iteration-04/` records the material pass; `review/final/` contains the final real Mobile/Metal captures. `review/03-render-material-study.png` is AI generated and is not a runtime screenshot. Render-led adjustments included broad readable masonry, timber grain, thinner sagging rails, sparse warm wall lights and red reflected light beneath the crossings.

The existing church shader, Valhalla floor/roughness maps, flame shader, audio and character meshes retain their existing project provenance. New runtime textures are original AI-generated production assets; the rendered review frames include those existing project assets.
