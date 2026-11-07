# Organic wall veins — two-stair art increment

On baseline `f950c54`, FIRST and SECOND had closed crimson tubes but regular cable-like U/S body loops. This pass replaces those two room networks with sparse authored asymmetric branching curves in `paths.json`, fitted to the current repaired masonry. Thick trunks now vary in width and taper into substantially thinner branches and fine capillaries. No hanging catenaries are generated in these two halls. Other room/passage root exports remain untouched.

The silhouette is guided in the wall plane rather than driven by turning around every individual brick. Depth uses the frontmost local stone support and a smooth envelope, preventing the repeated apparent breaks where proud stones used to hide the body. The underside fits back toward stone while the living crest stays rounded. Branch bases are fitted into their final parent tubes, and wall entries/returns retain complete buried-cap checks. Separate closed branches overlap intentionally at their joins.

Each focal bay also carries one original native merged nodule: two unequal ellipsoid lobes and a shallow rounded sealed tissue membrane. Voxel union blends the parts into one closed body, reduced to roughly4,000 triangles. Earlier extra Y arms were rejected because they read as thorns/fittings; the actual vein network supplies the branches. The native nodules have no extra free ports. Their rear sample vertices seat inside the actual closed backing, while only the front swelling stands proud of the main vessel. No filler cubes, cover props, lights or collision were added.

The local Krea source studies guide morphology only. H-017 also evaluated a local CL3D junction externally, but it was held from import at provenance review. No CL3D output file or vertices are in this game increment. The native sculpt is original project geometry built from curves, ellipsoids and a rounded membrane. `provenance.json` records exact native generator/design hashes, independent Krea references and reused material textures.

The existing fibrous tissue albedo/normal family is reused. Only duplicated FIRST/SECOND materials use its existing roughness texture; a second nodule copy is slightly wetter. The follow-up polish maps nodule fibres along the actual parent artery arc, softening the separate-patch texture transition; its diffuse tint is modestly lifted for the existing dark lighting. Other roots and every stone material keep their prior settings. Normal runtime cameras, torch placement and exposure are unchanged.

Rebuild from the project root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python-exit-code 1 \
  --python scripts/art/build_roots.py -- \
  --rooms first_stair_hall,second_stair_hall --passages none \
  --budget 15000 --mesh-budget 40000 --no-render
```

Current output: FIRST13 native vein components plus one nodule,11,504 triangles; SECOND12 plus one nodule,9,870 triangles. Total21,374 triangles versus50,846 at the previous baseline. This is a geometry count comparison, not a measured frame-rate claim. Both exports have closed topology, consistent winding, positive component volumes and valid shading normals. Native wall/parent cap checks cover32 terminal rings, and nodule checks cover45 rear vertices per hall. The independent exported check additionally tests all vertices and triangle centres over the full mitred walking ribbons, including grafts; it validates current source/model hashes as well.

Run `validate.py` with the existing CherninLab3D Python environment. `review/check.gd` checks actual loaded mesh/triangle counts, one nodule per hall,620 existing architecture collision shapes, seven stair-art meshes and isolated tissue materials. Traversal was run on the shipped organic geometry. The UV-only follow-up retains every triangle position; its fresh editor, mesh, material-isolation and full core-game receipts are also under `review/validation/`. Human input/camera feel and two-Mac Tailscale behaviour are separate.

`review/compare.html` pairs eight unchanged actual cameras with the previous game. `review/final/` has ten views × colour/albedo/object-ID/normals/collision, including two new junction close-ups, plus one3840×2160 wide view. They are unretouched Godot4.7.2 Mobile/Metal captures through the unfocused/silent wrapper. Diagnostic materials omit shader displacement and peeling. Native texture detail and low lighting remain deliberately restrained; human visual acceptance is not inferred from the mesh checks. The initial organic overview records `d4ce7dd`; the interactive comparison and final images include the later UV/tint polish. A triangle-position hash check proves that polish retains every exported triangle position. Known exit warnings (one ObjectDB, and seven texture RIDs in windowed captures) remain in the raw receipts.
