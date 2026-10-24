# Procedural wooden bridges (T-159)

Blender-baked decks, stringers, posts, handrails, rope rails and iron straps for the open wooden routes `high_span` and `low_span`. They are generated from the game's real route data, so the visible deck matches the walking collision.

## Rebuild

```sh
godot --headless --path . -s scripts/art/export_dungeon_layout.gd -- --out=$PWD/content/environments/procedural_bridge_v1/layout.json
blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_procedural_bridge.py -- \
    content/environments/procedural_bridge_v1/layout.json content/environments/procedural_bridge_v1 --samples 32
godot --headless --editor --path . --quit
godot --headless --path . -s scripts/bridge_construction_test.gd
```

Blender 5.2 is pinned by `scripts/art/procgen/core.py`. The default seed is 20261024. Re-baking the same layout produces byte-identical GLBs.

## Files

- `<route>.glb`: one `Wood_<segment>`, `Iron_<segment>` and `Rope_<segment>` node per route segment, in metres with Y up.
  - Every node carries glTF extras: `layout_hash`, `route` and `segment`.
  - Vertex colour R holds baked AO and G holds per-piece variation.
- `<route>.json`: the bake report (seed, samples, triangle and board counts, AO statistics, sha256).
- `layout.json`: the exported layout the bake used.
- `bridge_surface.gdshader`: the UV-mapped timber and rope material.
  - At runtime it takes the dungeon wood maps from `crypt_dungeon.gd`, so changes to materials (T-161) carry over.
  - The dungeon surface shader can't be used here: it maps grain by instance scale, and a baked deck has boards pointing every way in one mesh.

## How the deck fits the route

Godot's collision ribbon for a segment between nodes A and B with mitered half-widths EA and EB is `P(s, l) = lerp(A, B, s) + lerp(EA, EB, s) * l`.

- **Boards:** each lies along a line of constant `s`. Those lines are level, so boards sit flat on the ribbon with no stair steps.
  - At bends the boards fan out, and the gaps grow slightly on the outside, as on a real deck.
  - Board width is the narrowest local spacing minus 12 mm, so neighbouring boards never touch.
- **Stringers:** four per segment, two inner beams and two rim beams. They follow constant `l` and are mitered on the shared node line, so adjacent segments meet exactly.
- **Posts:** they stand outside the deck edge, bolted to the rim beam. They carry a mitered handrail and a catenary rope.
- **Supports:** transoms, piers and wall brackets stay in `DungeonStructure.support()`.
  - For baked routes, `BAKED_SEAT_DEPTH` puts the transom top exactly at the stringer bottom (`BAKED_STRINGER_BOTTOM`).
  - The bake adds iron straps where each stringer bears on a transom.

## Staleness

`DungeonStructure.layout_hash()` fingerprints each route's points, width and miters.
- If the hash stored in the GLB doesn't match, the game prints a warning and falls back to procedural timber.
- `scripts/bridge_construction_test.gd` then fails, because fewer crossings use a current bake.
- Pass `--no-baked-bridges` on the Godot command line to render the fallback for A/B captures.
