# Validation - 2026-10-23

Godot4.7.2; Mobile/Metal rendering. All windowed checks used godot_bg.sh.

- Asset validator:20 new native1254x1254 PNG maps, all nonempty; matching family dimensions.
- Headless editor import: exit0, no ERROR or WARNING lines in final import.
- Neutral and2x2 repeat material captures: exit0; MATERIAL_PREVIEW_OK for both.
- Scan-fragment and water/wetness captures: exit0; BRIDGE_PREVIEW_OK for all three.
- Two fixed-camera water frames differ at1.31% of pixels above3/255; mean RGB delta0.117/255. This verifies visible animation, not fluid simulation.
- Required scripts/smoke_test.py: exit0; PASS: local two-process ENet integration and disconnect cleanup.
- Capture and smoke runs retain ObjectDB shutdown leak warnings. No ERROR lines. No warning-free claim.

## Map conventions and visual review

Plaster and water native normals use DirectX green polarity. Their recipes set normal-map import and invertY=true. The wet shader defaults to scalar-height finite differences for coherent normal direction. Generated normals and roughness are not calibrated derivatives/parameters.

| Family | Source X slope correlation | Source Y slope correlation | Import Y flip |
| --- | --- | --- | --- |
| bridge_oak | 0.694 | 0.151 | False |
| mineral_plaster | 0.569 | -0.281 | True |
| damp_masonry | 0.574 | 0.387 | False |

The final wetness treatment softens coverage transitions, limits dry roughness to0.68..0.95 and darkens selectively. Wet regions react to actual lighting. Board geometry has varied angles/offsets and grain along its long axis.

Repeat previews show repeated stone/plaster landmarks. Native tiles are not certified seamless; large walls require UV/mesh divisions and broad blending. Roughness remains approximate and is range-limited by the wet shader.

Scan001 has a pale grayscale photographic atlas and a coarse725-triangle wall patch; smoothing removes faceted normals but it is not a finished hero asset. Scan002 provides a12000-triangle irregular wall patch. Both are open visual fragments, without collision, cap geometry or game-ready LOD acceptance.

These are material/shader/asset tests. The complete dungeon scene, navigation, character traversal and manual multiplayer acceptance were not implemented or requalified by this task.
