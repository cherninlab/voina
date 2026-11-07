# Broad actual-game inputs for local Krea

Baseline game commit `9e27ff9a`. Twelve distinct rooms plus upper/lower crossings, gallery and root tunnel. All 16 colour views were inspected; the first-stair view was moved from beneath the upper flight to its lower landing. No game geometry is changed by these review helpers.

64 1440 × 900 PNGs (colour, forward depth, inverse depth, world normals), camera/FOV records, a preview and hashes are at:
`/Users/theochernin/.codex/visualizations/2026/11/06/01a1b2e0-ab2f-7982-af93-111386c3dda3/dungeon-pack-9e27ff9a/`

The adjacent manifest records the immutable source hashes and shader conventions. Near-white inverse depth is computed in the shader before display encoding, with 30 m normalization and a black background. Depth overrides do not reproduce plaster peeling/displacement/transparency. Generated style concepts are not repair evidence.

Run through `scripts/godot_bg.sh --path . --script content/environments/red_descent/upper_crossing_v1/review/run_dungeon_pack.gd -- --dungeon --shading-ephemeral --explorer-capture --explorer-output=/absolute/output`.
