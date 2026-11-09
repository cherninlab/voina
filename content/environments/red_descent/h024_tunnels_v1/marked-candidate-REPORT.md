# H-024 diagnostic checkpoint

> Historical checkpoint: this page describes the candidate before Theo’s ten marked overlap defects. A new solid-stone rebuild is in progress; these earlier tests do not certify that rebuild.

State: **in progress, uncommitted, unshipped, not accepted**. The work is in the private `MultiPlayerProject-agents/theo-codex-tunnels-1` worktree, based on `89bc19d0`. This report is not a completion claim or an acceptance request.

[Open the complete visual review](marked-candidate-review.html): all **69 matched normal-lighting before/current pairs**, **28 inspection views**, and the failed iteration. Full PNGs are retained. Inspection views add a neutral camera light; normal captures use game lighting. Screenshots are actual Godot Mobile/Metal output, not concept art.

## Walls: confirmed texture cause

The new `Stone-rock_*` lining already had baked face UVs, but `stone_materials()` assigned the ordinary rock material with `mapped=false`. The vertex shader projects from changing vertex normals; on the curved lining this smeared and stretched the texture. A passage-only duplicate of the same material now enables `mapped=true`. The other shader settings, mesh and normal-lighting camera are unchanged. Compare `failed-iteration/rock-texture-smear.png` with `marked-candidate-normal/root_tunnel_2-back.png`; use the matched normal before/current gallery for baseline comparisons.

## Remaining visual issues

- **Fixed locally: stretched rock texture** (root_tunnel and cave_bypass): The new curved lining was assigned the unmapped rock material. That shader projects from varying vertex normals, stretching the scan into swirls. It now uses the existing baked face UVs. Same-camera normal-lighting result is in the gallery. No geometry changed in this last correction.

- **Unresolved H-024 geometry** (nave_5-forward, nave_6-back, return_gallery_4-forward and several root/cave joins): Junction roofs still have exposed backing and thin, radial or chopped stone remnants. Rock-to-masonry transitions have abrupt end faces. This candidate does not pass visual completion and is not being offered as finished.

- **Unresolved paving appearance** (root_tunnel_2-back and upper_cells views): Irregular raised flags, dark gaps and uneven contacts remain visible. The smooth walking ribbon passes the traversal test; that does not establish correct render geometry. Per-location collision/visual diagnosis remains necessary.

- **Present in matched baseline** (nave_5-forward, return_gallery_4-forward, ossuary_loop_0-forward, root_tunnel_5-back): Large near-camera planes also appear before H-024. They remain visible in the paired gallery. Their exact ownership and whether they are close walls, overlapping geometry or missing surfaces still need tracing; they are not being labelled proven holes.

- **Lighting and dressing remain weak** (cave_bypass, return_gallery, nave and room views): Several stretches are very dark; generic repeated fixtures and sparse rooms remain. Normal game captures are preserved. Inspection views add a neutral camera light and cannot establish that the normal lighting is acceptable.

- **Failed initial H-024 bake** (failed-iteration/chapel-blocked-opening.png): This was an introduced, unshipped regression. A generic clipping cap filled the inner arch as a solid face. Hole-aware caps and actual neighbouring clearance volumes removed the obstruction; the failed screenshot and failed traversal log remain included.

## Technical evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Editor import | Passed; corrected invocation output scanned for errors | [log](validation/editor-import.txt) |
| Core smoke | Passed, including two-process ENet checks | [log](validation/smoke.txt) |
| Actual capsule traversal | 1,235 m; descent, slopes, return, egress, four loops, both bridge lanes, deep-floor recovery | [log](validation/traversal.txt) |
| Structure | 23 fitted bearings, 191 framing/board members, 4 baked cloth pins | [log](validation/structure.txt) |
| Generator negative/positive controls | Passed: original sealed arch reproduced; repaired hole open, roof retained, manifold core, mirrored winding and varying collision profile | [log](validation/passage-selftest.txt) |
| T-196 four roof rays | E0275, E0277, E0334, E0336 hit front-facing rock and structural mortar; E0330 gallery control retained | [JSON](validation/roof-current.json), [log](validation/roof-probe.txt) |
| Normal capture coverage | 69/69 saved; no blank-frame failure or script error in corrected run | [log](validation/normal-capture.txt) |
| Inspection coverage | 28/28 saved; no blank-frame failure or script error in corrected run | [log](validation/inspection-capture.txt) |
| Protected repaired assets | Three stair GLBs and bones/cells/ossuary/window room GLBs are byte-identical to baseline | [hash comparison](validation/asset-comparison.json) |

Traversal, structure and crawler ran on the current geometry before the final material-only correction. Import, smoke, the roof probe and all captures ran again after that correction. Capture runs report a Texture RID shutdown leak warning; a prior capture run also reported an ObjectDB shutdown leak. These are not a clean resource-lifetime result. Manual camera/input, two-Mac Tailscale, performance, latency and thermal behavior remain unverified.

## Full crawler: issues remain

Same harness, full mode, seed 186, 36,000 ticks. Detector controls pass 22/22 in both runs. Visited **17,079 / 21,417** sampled walkable cells before and **17,061 / 21,537** currently. These are sampled exploration results, not proof of complete entrance connectivity. Geometry changes alter cell IDs and exploration paths, so aggregate count changes are not a quality score.

| Finding kind | Before | Current |
| --- | ---: | ---: |
| enemy_stuck | 1 | 1 |
| floor_collision_visual_mismatch | 12 | 14 |
| missing_floor_candidate | 100 | 100 |
| raised_render_surface | 100 | 100 |
| stuck | 37 | 32 |
| surface_backface_candidate | 100 | 100 |
| visible_ceiling_gap | 16 | 12 |
| visible_floor_gap | 59 | 60 |

The categories reaching 100 are capped samples. The one `enemy_stuck` report is the deliberate unreachable-goal detector fixture. Ray candidates are not all confirmed visible bugs. Current stalls remain in stair halls, choir, entry, other rooms and a few routes. No current sampled stall was reported in root_tunnel, cave_bypass or chapel_approach; that does not prove every route location is correct.

[Current summary](validation/crawler-current-summary.json), [baseline summary](validation/crawler-before-summary.json), [current raw issues](validation/crawler-current-issues.json), [paired comparison](validation/crawler-comparison.json). Source identity snapshots are alongside these files.

## Asset scope and recipe

Current outputs comprise 24 passage GLBs (10 route meshes and 14 nodes), the dependent gallery compatibility output, 32 refitted passage growth assets, and separate stair parapet coping (17 first-stair and 15 second-stair blocks). Existing repaired room/stair bodies and their vascular art were preserved. No external art was introduced; geometry comes from the existing procedural libraries and documented game materials. Ageing was not globally increased.

The initial bake was repaired with `scripts/art/repair_passage_caps.py`; eight skew nodes were rebuilt with `scripts/art/rebuild_passage_junctions.py`, using 24 wall templates and 16 paving templates. The current passage builder includes the corresponding geometric fixes. Gallery outputs were rebuilt with `build_upper_crossing.py`; passage growth was refitted using the existing `build_roots.py --rooms none --no-render`. The coping-only entry point preserves existing fixtures. This mixed incremental bake is not claimed bit-identical to a fresh full bake. Output/source hashes: [candidate files](validation/candidate-files.json).

Passage growth audit: 32 active indexed outputs, zero reported walking-corridor intrusion vertices and zero exposed terminal vertices. Attachment is not perfect: 53 sampled vertices deeper than 1 cm into stone; maximum sampled cling gap 0.059 m. [Raw audit](validation/passage-growth-audit.json).

## Reproduction

Use `/Applications/Godot.app/Contents/MacOS/Godot` (4.7.2) for headless import and `scripts/smoke_test.py`, `scripts/dungeon_traversal_test.py`, and `--headless --path . --script scripts/dungeon_structure_test.gd` for the focused checks. Windowed captures must go through `scripts/godot_bg.sh`. Capture arguments include `--host --dungeon --shading-ephemeral`, a unique `--port`, `--stone-rooms`, a `--views` filter, `--capture-keep-failures`, and an external `--capture-dir`. The inspection script is `capture_inspection.gd` in this folder.

The initial blocked arch and its failed traversal are retained under `failed-iteration/`. H-024 and T-196 remain unfinished because the visual work and shipment criteria are not yet met. Theo's requirement to review actual game results before accepting each builder remains in force.
