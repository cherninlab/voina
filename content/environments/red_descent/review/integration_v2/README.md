# Combined dungeon integration, second pass

Actual Godot Mobile/Metal captures, not ImageGen paintovers. This is a verified integration increment; it is not approval of the final visual target.

## What is integrated

- T-173: all 11 rooms use 496 generated flagstone/kerb modules. Same-height legacy doorway ribbons are clipped visually. The original room and route collision triangles remain unchanged (floor owner audit: `4f909a6e2ffe26bc4e130f387ce74f79a033348b941b96380bacd75072df3fc6`). Floor relief casts no shadow; baked AO and received shadows remain.
- T-163: eight sparse settled rubble piles, with 149 convex bodies at baked scale and three visual LODs. Stones use Rocks025; broken boards retain their own along-grain Wood035 UVs. Candidate piles that obstructed routes/pilasters were rejected before placement. Exact origins and asset IDs are in `dressing.json`.
- T-164: ten banners, tapestries, drapes, ropes and corner webs fitted to actual nave, bell and restraint framing. The supplied material presets interpret vertex AO/variation/wear correctly. No decorative collision was added. Existing bridge cloth and incompatible sheet webs were left to their owners.
- Two permanent nave torches have paired iron brackets anchored into the room walls. The lamps sit off the cloth plane so they illuminate its faces. These are part of the playable scene, not capture-only lamps.
- T-169 first aged bridge bake is included from main. T-174 visible ageing remains owned by theo-claude-14; this integration does not modify its generator or assets.

## Attachment corrections

The independent reviewer found that a web touched the ideal post bounding box but missed its chamfered surface by about 11 mm. Moving the web origin 30 mm inward corrected it. The audit now measures actual transformed hewn-mesh triangles as well as nominal member dimensions. Current maximum socket transform error is below 0.5 micrometres; actual pin-to-wood distance is 5.6 mm, and web-to-wood distance is 1.4 mm. Visible iron nails bridge the cloth pin clearances.

`dungeon_dressing_test.gd` checks floor/back-wall support rays, actual sculpted contacts, expected imported hull count, unit body/shape scale, all route ribbons and hanging headroom. It also ray-checks the four high-torch bracket anchors against actual masonry. The minimum conservative rubble AABB clearance beyond a walking ribbon is 1.182 m.

## Verification

Saved after the restart in `checks/`:

- Headless editor import: no script/import errors.
- Dressing audit: 8 piles, 10 hangings, 149 hulls, 11 room floors, four masonry bracket anchors; no failures.
- Structure audit: 23 fitted bearings, 203 framing/board members; actual wall anchors and lower routes clear.
- Bridge contract: 2,592 sideways capsule sweeps held; two baked decks within 14 mm of collision at 548 lane samples (declared missing-board footprint excluded by the bridge owner's contract).
- Real-player traversal: 1,276 m, slopes/descent/return/egress/four side loops/both bridge lanes/deep-floor recovery.
- Main smoke and dungeon smoke pass, including two-process ENet, finite encounter, late join and map selection/adoption.

The existing one-ObjectDB-instance shutdown warning remains in standalone tests. Windowed capture shutdown also reports seven texture RIDs; captures and test markers succeed. These warnings have not been represented as fixed. Manual camera/input, two-machine Tailscale play and uncapped performance were not tested here.

## Visual evidence and current limit

`first/` contains the initial 14 assembled frames. `after/` contains the final refreshed same cameras, including the corrected web contact, permanent nave lamps off the cloth plane and the T-175 floor material calibration. Views 09–14 expose entry flooring, restraint sockets, nave framing, bell hangings, chapel wall spill and choir debris. Views 01–08 preserve the earlier comparison cameras.

The first review found black/noisy rectangular stone patches, also present in the floor-only T-173 captures. T-175 retained 14 controlled comparisons, including a verified shadows-off run with the dungeon light updater stopped. Constant ALBEDO removes the blotches; no specific renderer fault was proved. A separately reviewed material calibration (`4edfdd7`) reduces compounded darkening: tint `(0.88,0.85,0.80)`, variation `0.14`, diffuse AO weight `0.25`, grime `0.15`. Actual textures, normal maps, AO output, roughness, geometry and lighting remain. In three fixed floor ROIs, pixels below display luminance 0.05 fell from about 15–21% to 1–9%. This is a material response improvement, not a claim that an engine fault was fixed or every speckle removed. The separate solid square under a torch is a real fixture shadow.

The visible ageing of the wide bridges, repeated large wall/ceiling treatments and overall reference-level material quality remain further art work. Counts and successful traversal do not establish visual acceptance.

## Coordination

T-162, T-163, T-164, T-165, T-169 and T-174 have received board notes for scope, attachment contracts and findings. Floor integration shipped separately as `802ccc7`; bridge first ageing as `1e8718c`. Parent edits are limited to the crypt caller, dressing helper/test and capture harness. No bridge/physics-generator files are changed here.

## Separate target paintover

`paintover-06-target.png` was made with the built-in ImageGen tool from the final `after/06-descent-overlook.png`; it is **not a runtime screenshot**. The exact prompt is saved in `paintover-prompt.txt`, source/output SHA-256 in `paintover.json`. The target preserves the camera, bridge path, openings and visible lower crossings, while improving oak grain/edge damage, attached fasteners, scanned stone/plaster breakup and a forged open torch basket. These are future asset/material targets; they are not represented as already implemented meshes or maps.
