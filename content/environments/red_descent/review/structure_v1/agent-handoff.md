# Separate workstreams

The user is starting a parallel procedural wooden-bridge builder. Do not start a competing bridge generator or modify that agent's output while it works.

| Workstream | Owned code/assets | Boundary |
| --- | --- | --- |
| Procedural wooden bridges — user's parallel agent | `gameplay/environment/dungeon_structure.gd` bridge methods; new assets/build scripts under a dedicated bridge folder | Own plank profiles, joints, rails, sag, support fit and bridge bake. Preserve route grades and lane clearance. The existing deck is a rejected candidate. |
| Masonry construction | `gameplay/environment/red_descent_geometry.gd` room/vault/arch/pilaster functions; dedicated masonry assets | Window reveals must be part of thick masonry, eliminate pasted-on rectangular panels and stacked-column discontinuities. Do not change `build_path`, `beam`, `flush` or bridge-helper contracts without integration coordination. |
| Materials and shading | `content/environments/red_descent/dungeon_surface.gdshader`; dedicated material review output | Fix physical material scale, broad/medium/fine variation, dry versus damp response and pervasive texture repetition. No bridge mesh edits. Preserve shader parameter names used by the level. |
| Integration and evidence — this agent | `crypt_dungeon.gd`, capture/test integration and review folders | Merge verified outputs, rerun construction/traversal checks, capture actual frames, then paint over those frames. Any shared-file change must be coordinated through board claims. |

## Bridge inputs

- Routes: `RedDescentLayout.routes()` entries `high_span` (3.2 m) and `low_span` (3.6 m). Both are sloped, skewed polylines; crossings at different heights must remain separate.
- Current entry point: `DungeonStructure.route(path, edges)`, invoked once per exposed path by `RedDescentGeometry.build_path`. `edges` are the shared miter offsets at route nodes. The stone `central_ledge` also uses the helper for its underlying supports; preserve that caller until explicitly replaced.
- `RedDescentGeometry` retains the continuous collision ribbon and invisible guard collision. Review visual-versus-collision agreement when replacing the deck.
- Current helper also contains `roof(room)`, used by the nave, and fitted general-purpose `timber(...)`, called by bell framing. Preserve those or coordinate extraction; replacing this file wholesale would break unrelated construction.
- Three shape variants and one CL3D bearing capital are in `content/environments/dungeon_structure_v1/`; use or discard the current deck mesh. A cloth example demonstrates two pins, Blender gravity simulation and static export with a bake report.
- Existing support audit is `scripts/dungeon_structure_test.gd`. It checks real wall contact, lower-route intrusion, required bearings and roof connections. Update the contract if the bridge implementation changes the record shape.
- Walking validation: `python3 scripts/dungeon_traversal_test.py "$GODOT"`. It walks the actual capsule for 1,276 m, including both bridges at +/-0.75 m from center.
- Before/after frames: `../paintover_v3/runtime/` and `runtime/`. The latter is the connected baseline, not an approved bridge appearance.

Use separate worktrees and board claims. Each owner should provide actual screenshots, test commands/results, source commit and remaining defects. Asset counts and an import passing are not visual acceptance.
