# Validation - 2026-10-23

Godot 4.7.2 stable; Mobile/Metal for windowed captures.

- Asset check: 33 nonempty native PNGs, all 1254 x 1254; family dimensions match; six StandardMaterial3D resources.
- Initial and configured headless editor imports: exit 0, no ERROR or WARNING lines.
- Real background-window capture: exit 0, MATERIAL_PREVIEW_OK for neutral and 2x2 repeat views at 1800 x 1200.
- Required scripts/smoke_test.py: exit 0; PASS: local two-process ENet integration and disconnect cleanup.
- Smoke and capture logs retain ObjectDB shutdown leak warnings (also seen before this material work). No ERROR lines. This is not a warning-free run.

## Material review

Six materials read distinctly under identical light. Dry plaster and limestone are kept less deeply embossed than rubble. Floor and wall stone are intentionally separate sizes. Oak whorl and some broad stone landmarks visibly repeat in the 2x2 view; these tiles are not certified seamless. Use mesh divisions and blend masks at scene scale.

Normal/height slope correlations are sampled diagnostics, not a calibrated scan or proof of exact per-pixel derivatives:

| Material | X | Y |
| --- | --- | --- |
| red_lime_plaster | 0.51 | 0.308 |
| rubble_masonry | 0.673 | 0.444 |
| pale_limestone | 0.531 | 0.329 |
| broken_stone_floor | 0.701 | 0.402 |
| aged_oak | 0.474 | 0.239 |
| oxidized_iron | 0.45 | 0.151 |

Limestone normal attempt2 was accepted: Y correlation improved from -0.004 to +0.329 while preserving macro features. Rejected candidates remain recorded by native source path; only accepted maps are delivered.

No gameplay geometry, collisions or level lighting were changed. No new character traversal or manual multiplayer acceptance is claimed for this material-only task.
