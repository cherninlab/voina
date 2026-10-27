# E01 quality experiments

The eleven single-image TripoSG/TRELLIS attempts did not resolve the requested multi-view problem. They remain local diagnostics; none replaces the shipped `../e01_crawling_v1/` model. `attempt_summary.json` records their assessment.

The user rejected both generated four-view sheets: first for inconsistencies, then for twisted/broken legs. Their local receipts preserve that status; rejected sheets and raw reconstruction meshes remain local diagnostics. No 3D reconstruction has run from those sheets.

The current direction is [female_ik_v4](female_ik_v4/README.md): reuse the actual CC0 female character, solve a fixed pose with inverse kinematics, and render all four views from that single mesh. The actual hips and chest supply alignment cues. The rig, static GLB, transparent views, editable target controls and checks are included. This delivers a coherent pose foundation; statue detail and user visual approval remain open.
