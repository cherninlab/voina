# Stair vascular repair — actual game increment

This refits only FIRST and SECOND stair-hall growth on main `1fe4d60` (including the existing ritual stair art). The native root generator now imports the exact current recessed wall cores, closed vaults, fitted stairs and wall fixtures when their source/layout guards match. Stone, stair art, route/collision, lighting and runtime materials are unchanged.

The original skin had deliberately open child bases, sharply twisted coarse sections and an extra cone beyond buried ends. Final settling also moved parent vessels away from their old branch attachment positions. The repair closes each branch, softens longitudinal folds, uses rounder sections, refits branch births into the final parent tube and fits complete wall terminal rings into actual backing. Wall necks narrow along the worn stone before their final burial. Free terminations retain longer tapers. A stable orthonormal frame prevents a nearly wall-normal cap collapsing into a line. Export shading is computed on the actual triangulated surface, with flat hidden caps.

The separate export check also caught growth above the outside mitre of the second stair: the old centre-line capsule rule missed this part of a bend. Native clearance now includes the actual walking-ribbon triangles as well as its existing margin. One system that could not be refitted while preserving this clearance was omitted. No filler blocks, cover membranes or additional lights were added.

The two exported GLBs contain 91 closed branch components in eight wall batches: FIRST26,358 triangles; SECOND24,488. The final budgets are30,000 per room with the original15,000 growth budget. All118 wall/parent terminal rings have their complete caps buried (63 wall entries/returns and55 parent mounts). The baseline exports had334 open boundary edges; the new exports have zero boundary/nonmanifold edges, consistent winding, positive component volumes and valid shading normals. Both the native clearance audit and independent vertices/triangle-centres check over the full walking ribbons pass. Separate closed branch volumes still overlap intentionally; the whole network is not Boolean-fused.

Rebuild from the project root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python-exit-code 1 \
  --python scripts/art/build_roots.py -- \
  --rooms first_stair_hall,second_stair_hall --passages none \
  --budget 15000 --mesh-budget 30000 --no-render
```

Run `validate.py` with the existing CherninLab3D Python environment for source/GLB hashes, topology, winding, normal and route checks. `review/check.gd` verifies the actual loaded batch/triangle counts, original crimson fibrous material,620 architecture collision shapes, seven stair-art meshes, and no growth collision/lights. `review/probe.gd` traces the four disputed image positions to actual runtime growth triangles; they include partially stone-occluded body bends, not just caps. Final wall/parent burial is checked during generation against the exact skinned rings and solid geometry; the independent exported check does not repeat that algorithm.

`review/compare.html` pairs six unchanged cameras against the previous stair-art game captures. Two additional grazing views expose attachments from the side. Each view has colour, albedo, object-ID, normals and collision passes; the wide first-stair view is3840×2160. These are unretouched actual Godot4.7.2 Mobile/Metal output through the unfocused/silent wrapper. Diagnostic materials omit shader displacement/peeling. `provenance.json` records native source, reused materials and the local H-014 Krea reference pack. Krea guided morphology only; no inferred mesh or invented architecture was transferred. The local CL3D environment supplied independent mesh inspection, not inference.

This is a structural/refitting increment, not final organic-art acceptance. Some long loops still read as uniform cables and some bends disappear abruptly behind proud stones. Branch-to-parent necks are closed overlapping volumes rather than a continuous sculpted bifurcation. Those visible morphology limits require another focused art iteration. Other room and passage GLBs were not rebuilt or certified by this pass. Human art acceptance, manual input/camera feel and two-Mac Tailscale performance remain separate from the automated checks.

Validation receipts are under `review/validation/`; editor import, actual runtime checks, traversal and the isolated core suite are recorded there after the final rebuild. Known engine teardown warnings (one ObjectDB; windowed runs also seven texture RIDs) are retained in the logs.
