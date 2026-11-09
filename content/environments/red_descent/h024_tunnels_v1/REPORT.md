# H-024: actual-game diagnostic build

**Progress shipped; builder incomplete and not visually accepted.** Code and generated assets are on `origin/main` in [f2504af0](https://github.com/cherninlab/voina/commit/f2504af050c0871d95408af0d99159d86ad38f7f), following Theo’s explicit push request. This review is a progress record, not a completed-builder or acceptance claim.

[Open all normal and inspection views](review.html). The review retains 69 matched normal-lighting pairs, all 28 inspection views, the earlier marked candidate and rejected iterations. Inspection adds a neutral camera light; normal views use game lighting. These are actual Godot Mobile/Metal captures.

## What the marked images revealed

These are shared assembly defects, not cosmetic texture touch-ups:

- **Wall texture mapping:** the curved rock lining had baked UVs but received an unmapped material. The per-vertex projection smeared the scan. Passage rock now uses baked, face-based world coordinates consistently across runs and bays.
- **Overlapping walls and backing:** old open-backed templates and independently cut run/bay meshes left cap plates, fragments and mortar ahead of stone. Passage walls now build from closed templates with actual arrival clearances and recessed backing. Fresh source generation replaces incremental repairs for the current passage outputs.
- **Hewn junction mismatch:** the comb pattern exposed the mortar body through the rock skin. One marked ray hit mortar approximately 0.34 m before the rock. A single hewn barrel chamber with actual incoming openings makes the focused regression hit rock before mortar. **Residual striping is still visible in the complete scene’s cave inspection**, despite that ray passing; this remains unresolved and is not labelled fixed.
- **Double floors and floating patches:** a fallback ribbon could overlap baked flags even when its segment midpoint lay outside the baked stretch. Render clipping now uses the actual overlap while retaining walking triangles. Sloped flags fit the same subdivided mitred walking surface. Portal cores no longer carry a flat floor plate across chipped flags or ramps.
- **Arbitrary floor cuts:** runs, bays and the nave landing now share a deterministic staggered paving field. Independently clipped pieces retain the same stone, tone and UV origin. The seam regression checks matching surface/UVs across two builders. This does not settle every existing room/stair material transition.
- **Near-camera hallway walls:** shaft clearances previously required the route centreline to cross each wall face. At a corner, the adjacent face remained across the tunnel. Enclosed routes now clear their actual padded ribbon; open ledges retain the previous crossing and room-doorway rules. Positive and negative controls cover both.
- **Nave-to-ledge connection:** a separate H-023 prototype replaces the endpoint bracket stack with one continuous masonry arch reaching the existing ledge pier and shaft wall. One paving field continues through the portal. It is a single landing interface, not completion of every bridge.

## Latest eight marks

| Mark | Location | Current disposition |
| --- | --- | --- |
| 1 | nave_0-back: corridor/ledge landing | Continuous support and paving prototype built; shown in game. Still subject to visual review. |
| 2 | chapel_approach_0-back: room/landing connection | The room parapet and threshold still read poorly. Existing stair/room bodies were preserved; the overall composition needs further work. |
| 3–4 | cave_bypass_2-back: broken wall faces | Rebuilt as one hewn chamber and lining. The focused mortar/skin ray passes, but residual full-scene striping remains open. |
| 5 | chapel_approach_1-back: junction wall fragments | Passage boundary rebuild applied. The masonry cut-edge treatment remains an open visual concern. |
| 6 | nave_5-forward: large hallway blockage | Adjacent shaft face cleared; real captures show the corridor again. |
| 7 | nave_5-back: floor/room edge | Shared floor ownership/height fixes applied. The existing room-to-passage transition remains under review. |
| 8 | nave_5-forward: straight paving cuts | Shared paving field removes the independent run/bay tile pattern. Lighting and the existing room floor remain separate visual concerns. |

## Open work: do not accept this builder yet

- **Root exit / low-span turn:** the corridor portal faces outside the shaft while the bridge turns sideways. The marked blue ray found no render mesh within 80 m and does not cross the shaft outline in plan. This needs a composed turning interface with the bridge-facing opening; calling it fog or covering it with another small block would not resolve the layout.
- **Masonry junction finish:** cut stone ends, awkward roof intersections and exposed cross-sections still need a coherent facing treatment, particularly around the nave/chapel joins. Removing every cap exposed holes; the rejected experiment is retained.
- **Room and stair transitions:** preserved stair bodies, room floors and parapets still produce abrupt material changes and poorly explained half-height walls. Passing traversal does not make those views acceptable.
- **Lighting/dressing:** some passages remain dark and use repeated fixtures. Neutral inspection lighting is diagnostic, not a lighting acceptance result.
- **Survey and growth candidates:** the crawler still reports unresolved candidates; growth attachment/clearance is reported with its raw audit rather than declared perfect.

## Rejected iterations and provenance

The earlier marked candidate is available in [its original review](marked-candidate-review.html). `iterations/` retains the pre-fresh checkpoint and the rejected wider-cut/cap-removal views; `failed-iteration/` retains the initial sealed arch and texture smear. No failure images were discarded to make this checkpoint look complete.

The current passage outputs come from `rebuild_passage_junctions.py` with all ten enclosed route IDs, using the corrected builder and closed libraries. The dependent gallery is built with `build_upper_crossing.py -- --gallery-only`; passage growth uses `build_roots.py -- --rooms none --no-render`. Empty root rebuilds now remove stale generated files. The nave landing is generated separately by `build_nave_abutment.py`.

Existing room, repaired stair/wall and vascular GLBs are protected by a byte-hash comparison. No external art was added. Ageing remains restrained; no global ageing increase was used as a repair.


## Verification of the published progress snapshot

| Check | Result | Evidence |
| --- | --- | --- |
| Source rebuild | All 24 passage assets: ten enclosed routes and fourteen nodes | [log](validation-current/source-bake.txt) |
| Editor import / core smoke | Passed; local two-process ENet checks included | [import](validation-current/editor-import.txt), [smoke](validation-current/smoke.txt) |
| Actual capsule traversal | 1,234 m, descent/return/loops/bridge lanes/recovery | [log](validation-current/traversal.txt) |
| Structure | 23 bearings, 184 members, four cloth pins | [log](validation-current/structure.txt) |
| Focused geometry/seam controls | Passed | [generator](validation-current/passage-selftest.txt), [floor/corner controls](validation-current/floor-overlap.txt) |
| Chapel bad-mesh control | Old stone wall at 2.888 m; fresh route clear for 20 m | [log](validation-current/chapel-regression.txt) |
| Export audit | 25 passage/landing GLBs reimported; finite coordinates, no validation repair | [JSON](validation-current/mesh-audit.json) |
| T-196 roof positions and E0330 control | Front-facing structural hits retained | [raw rays](validation-current/roof-current.json) |
| Game capture coverage | 69/69 normal and 28/28 inspection, plus one support underside inspection | [normal](validation-current/normal-capture.txt), [inspection](validation-current/inspection-capture.txt), [support](landing-inspection/nave-landing-support-inspection.png) |
| Protected models | 31 existing room/stair/wall/vascular GLBs byte-identical to the recorded baseline | [hashes](validation-current/protected-assets.json) |

Blender issued mesh-validation warnings during export; the exported files were reimported and validated without further repair. Capture runs report Texture RID shutdown leaks; standalone checks also report ObjectDB shutdown leaks. The marked-wall diagnostic additionally reports resources still in use at exit; its rays are diagnostic evidence, not a clean resource-lifetime test. Manual camera/input, two-Mac Tailscale, GPU cost, latency and thermal behavior were not measured.

Full crawler: **22/22 detector controls pass; 17,236 / 21,616 sampled walkable cells visited; 415 candidate findings**. Unvisited cells are untested, not proven unreachable. Geometry changes alter survey paths, and several categories cap at 100; aggregate changes are not a quality score.

| Candidate kind | Count |
| --- | ---: |
| enemy_stuck | 1 |
| floor_collision_visual_mismatch | 13 |
| missing_floor_candidate | 100 |
| raised_render_surface | 100 |
| stuck | 33 |
| surface_backface_candidate | 100 |
| visible_ceiling_gap | 7 |
| visible_floor_gap | 61 |

The one enemy-stuck entry is the intentional unreachable-goal fixture. Other survey findings remain candidates requiring local confirmation. [Raw issues](validation-current/crawler-issues.json), [coverage and limitations](validation-current/crawler-REPORT.md), [telemetry](validation-current/crawler-telemetry.json).

All 32 active passage-growth reports match their current source GLBs. Their raw audit still flags **three walking-corridor vertices** (root_tunnel_0_421), **ten vertices deeper than 1 cm into stone**, and a maximum sampled attachment gap of **0.059 m**. Do not read this as perfect attachment. The empty-output cleanup regression was exercised on the earlier short-stretch candidate; the fresh source rebuild subsequently generated valid growth at all 32 stretches. [Audit](validation-current/passage-growth-audit.json).

H-024, T-196 and the narrow H-023 landing work remain in progress on the hosted board. The explicit push request authorizes progress publication; it does not establish visual acceptance.
