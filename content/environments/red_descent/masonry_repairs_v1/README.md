# Choir/stair mortar and junction repair — H-007 / H-008

The choir's bright specks hit existing solid front-facing mortar/stone triangles. Its source mortar meshes are closed. A matched matte control removes the specks without changing geometry, identifying wet fine-scale shading as a contributor. Mortar now uses a separate opaque, rough native material. The stone surface keeps its colour/maps with restrained normals and rough damp areas. Crimson vascular colour follows the user's correction in the parallel art chat.

The two stair-vault backing meshes were genuinely open sheets. The owning vault generator now gives each web 0.24 m of roof-side thickness and closes cut rims. The repair bake unions webs into one connected watertight shell per room. Independent exported checks find zero boundary/nonmanifold edges and preserve the original intrados vertices within 0.000005 m. Source-hash and native-precision room guards preserve the original asset on mismatch. The matching original vault collision is replaced once, rather than duplicated.

Three recent upper bridge bearing/socket patch blocks and the rough inferred-rock overlay were removed from the live game. Existing timber brackets, masonry arches, piers, wall relief and room foundations remain. No replacement filler boxes were added. The rejected rock sources stay preserved for provenance.

`review/before/`, `review/matte-control/`, and `review/after/` are actual game captures. Eight angles include choir walls, both stair halls from upper/lower or side views, and the upper connection. Each has colour/albedo/object IDs/normals/collision. `review/compare.html` pairs the colour views. Debug passes omit shader peel/displacement; coloured contacts are not an exhaustive intersection test.

Checks: editor import; connected/watertight exported meshes; 197/200 sampled new-shell collision matches, 270 cement and 480 shaft-relief matches; single replacement collision bodies and stale-room rejection; 1,235 m capsule traversal; full core suite PASS in an isolated run. Earlier concurrent runs hit a teardown RID error and a snapshot-startup timing failure; the isolated suite is not a hardware/network performance result.

Continue: bare stair-body ends and jagged tread joins are still visible. The next increment rebuilds those with native fitted stone facings and mitres. This first increment seals the backing and removes the identified patch masses; it does not declare all junctions finished.

Rebuild: `/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python-exit-code 1 --python scripts/art/build_masonry_repairs.py`. Validate with the CherninLab3D Python environment and `validate.py`.
