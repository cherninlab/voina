# T-171 review evidence

## Actual engine screenshots

![Ten CL3D source props, actual Godot Mobile captures](cl3d_v1/godot/all-props.png)

Source order, left to right: table, bench, shelf, barrel, coffin body; second row coffin lid, skull, femur, pot, candle holder. Full individual 1280x720 files are in `cl3d_v1/godot/`.

![Twelve baked dressing sets, actual Godot Mobile captures](physics_v1/godot/all-sets.png)

Columns: refectory, mortuary, ossuary, votive. Rows: calm v0, mild tremor v1, strong tremor plus rolling stone v2. Heavy pots are genuinely fractured into three cells. The screenshot sheets concatenate original rendered pixels without a creative redraw. Asset shaders are neutral review clay.

## Other evidence

- `references_v1/`: ten original ImageGen inputs, exact prompts/receipts, unchanged hashes, recorded user image approval.
- `cl3d_v1/*-front.png`, `*-back.png`: twenty actual Blender source review renders. `all-props-front.png` / `all-props-back.png` concatenate them. `rejected_unmasked/` preserves before-frames from the rejected shadow-fused pass.
- `physics_v1/*-front.png`, `*-back.png`: actual Blender baked-set review views; `all-sets-front.png` follows the same four-column/three-row order.
- `physics_v1/*-attempts.json`: attempt-level physics validation. Successful current outputs are indexed in `../../../procedural_props_aged_v1/sets.json` (use the runtime pack README for details).
- `cl3d_v1/checks/`: accepted and historical generation/physics logs, final editor import, actual engine capture/audit, mesh audit, and ENet smoke. Older failed logs are retained intentionally as an audit trail; current final pass is identified in `verification.json`.

## Acceptance boundaries

Technical mesh/physics/import review is complete. No dungeon placement, room traversal, material finish, manual camera/input or two-machine network acceptance is claimed. Image approval preceded CL3D and is not recorded as final approval of derivatives. Full dimensions, collision policy, suggested placement, provenance and reproduction are in the runtime pack README.
