# Woodland village arena

VALKA's arena is a roughly 56 m woodland settlement with asymmetric cottage clusters, angled palisades, a market clearing, an off-center well, and a ramp-connected lookout. The collision ground is an original gently uneven mesh. A separate original noise-shaped landscape continues beyond it into foothills and distant ridges; those distant slopes are cosmetic.

The central spawn axis remains clear. The original four cover collision footprints remain in place beneath detailed paired crate visuals. Cottages, tables, well, barrels, palisades, lookout and ramp have static collision. Source model scaling is uniform. This scenery does not own networking, combat, player movement or match rules. Mik's fisheye shader is unchanged.

## Visual targets and supporting assets

`content/environments/village_generated/reference_sets.json` pairs each generated composition target with its supporting assets and geometry. The two `target-*.png` images are AI concepts, **not game screenshots**. Prompts and provenance are stored beside them.

The first material pass adds original ImageGen compacted-path and flax-weave base colors, curved sagging market canopies, clustered opaque grass with upward-biased normals and backlighting, and more surrounding trees. Ground and prop textures use mipmaps, anisotropic filtering and VRAM compression. The cloth dye is explicitly converted from sRGB to linear shader color. Generated materials remain artistic candidates rather than calibrated PBR scans.

The tree pack's preview ground plane is removed from its village instance: it previously intersected the uneven terrain and produced flat green patches. Trees beyond the fence follow the actual landscape triangles, avoiding floating placements at unsampled noise peaks.

## Imported asset provenance

Selected user-authorized KitBash Valhalla cottages, well, wagon, barrels, shield, dummy, rocks, tables, baskets and crates are exported by `scripts/export_valhalla.py`. `--assets=crate,basket,table` updates a subset while retaining the existing provenance entries. Shared PBR textures are capped at 2048 pixels; commercial source provenance and user authorization are recorded in `content/environments/valhalla/provenance.json`. Source Blender files are not included.

No geometry, textures, armor or sounds from the earlier commercial Village House Kit / CLO / Ghosthack archives are included. Existing trees retain their repository provenance.

## Real runtime captures and collision checks

```sh
"$GODOT" --path . --script scripts/capture_village.gd -- --host --port=7793 --capture-dir=/absolute/output/folder
```

The script probes spawn floor, ramp and lookout; drops the actual player at four terrain locations and requires it to land; then saves three 1600 × 1000 images from the actual Metal renderer. The explicit art-capture script hides the local menu/HUD layer so focus-loss pause panels cannot obscure scenery. The build identifier and fisheye remain active. Normal play is unaffected by this capture-only camera.

Run `"$GODOT" --headless --editor --path . --quit` and `python3 scripts/smoke_test.py "$GODOT"`. Headless/loopback checks do not establish human camera feel, four-player acceptance, Tailscale behavior, M2 frame rate or thermal performance. Visual quality is still below the references: the lookout construction, foliage assets, lighting depth, material repetition and landscape dressing need further passes. Buildings remain closed shells.

## Lookout construction pass

The generated roof construction sheet is paired with an original reed-thatch base color. Godot geometry uses inward rafters, tie beams, king posts, knee braces, irregular roof eaves and separate rail planks; the generated sheet is a visual reference rather than exact CAD. The existing ramp collision remains one smooth surface beneath decorative deck boards and handrails. Roof/ground/player checks and real captures accompany this pass.

## Sky and fog pass

The supporting `daylight_sky.png` is an original generated LDR appearance panorama, not an HDR lighting capture. A sky shader adjusts its generated horizon latitude and softens wrap/pole discontinuities. Fog still affects distant geometry, while `fog_sky_affect = 0.08` preserves cloud detail. A real-render comparison at 1.0 versus 0.0 confirmed that the previous full sky-fog influence was hiding the procedural clouds entirely. Panorama prompts and reference associations are recorded with the texture.

## Groundcover shape pass

The generated groundcover study is paired with solid, three-segment tapered grass strips in `green_borders()`. Generated alpha cards were rejected for fringes and clipped silhouettes. Geometry needs no transparency sorting or alpha edge filtering. The earlier empty-probe diagnosis was misleading because dummy headless rendering does not expose the same capture data as Metal.

## Surrounding landscape material pass

Original generated schist replaces the paving texture on distant exposed terrain. Triplanar mapping avoids vertical stretch, broad color variation breaks repetition, and the surrounding visual terrain uses a 3m sampling grid. Rock shelves are distributed across the slopes instead of a ring; 320 trees occupy the surrounding land. These outer visuals do not expand the playable collision boundary. No M2 performance acceptance is implied.

## Ridge silhouette pass

The paired schist-valley target guides domain-warped ridges, smaller crags and softened rock strata in the distant height field. Vegetation and rock placements still interpolate the exact rendered triangles. The playable terrain height and collision remain independent.

## Ground stone dressing

Low-profile opaque stone geometry uses the paired generated schist material. Deterministic clustered scatter avoids the central duel space, main path center and x=0 test axis. Stones are cosmetic and have no collision. The full reference look remains unachieved; this pass adds genuine ground silhouettes rather than more texture noise.

## Experimental static lightmap preparation

Run `"$GODOT" --path . --script scripts/prepare_village_bake.gd` with the real renderer, without `--headless` or `--editor`, then open the generated `village_lit.scn` and use Bake Lightmaps. Preparation unwraps selected static meshes and adds explicit probes. It replaces the snapshot and clears its light data, so finish the editor bake before running or shipping the level.

Headless inspection incorrectly suggested missing probe data. A Metal load of the baked resource shows populated probe positions. Preparing the snapshot with dummy headless rendering also lost MultiMesh instance buffers; the helper now refuses that mode. The Metal-prepared snapshot retained 5,076 grass instances and 1,167 stones in validation. The subsequent solid-surface rebake passed runtime review and is shipped as described below.

AgX/lower-fill trials were rejected after actual captures looked flatter or underexposed. Live tone mapping remains ACES; directional shadow bias is reduced to improve contact placement. No GI quality or performance acceptance is implied.

## Enabled static indirect lighting

The verified solid-surface snapshot is now loaded by the village builder when present. The source builder remains the regeneration path and preparation explicitly bypasses the saved snapshot. After changing source geometry or lighting, regenerate and rebake before shipping the snapshot together with its data and texture. Two-sided roof/canvas surfaces retain their regular lighting: one shared UV2 chart produced black reverse faces when baked. Solid posts, rails, walls and terrain use static lightmaps, with realtime sunlight retained.

The accepted Metal snapshot preserves both MultiMesh scatters and passes floor/ramp rays and actual player drops. It contains 491 baked mesh instances; the generated light texture is about 3.8 MiB. The packed geometry snapshot is substantially larger and stored with LFS. This improves local indirect-lighting depth but remains far below reference quality; no M2 performance acceptance is claimed.

## Soil material correction

The valley target is paired with an original 2.5m soil/gravel albedo candidate. Paving normal and roughness now contribute only to visible paving patches rather than the whole dirt path. Terrain tangents are generated for the normal-map basis; soil is high roughness with a flat normal rather than invented displacement. The source and baked snapshot are updated together. Generated albedo does not constitute a calibrated PBR scan.

## Layered clover groundcover

The actual-Enshrouded target is paired with the groundcover shape study and original opaque clover leaf geometry. A deterministic low foliage layer fills irregular edge patches around existing grass while leaving the court and primary routes clear. It has no collision, transparency or shadow-card sorting. This live foliage is deliberately excluded during static bake preparation and added after loading the baked village, so it is not duplicated in subsequent snapshots. Its density and leaf detail are still below the reference; no M2 performance claim is made.

## Structural timber material

A generated aged-timber albedo is paired with the actual-Enshrouded target. Posts and cylindrical braces use local longitudinal mapping rather than the wall-of-planks world projection; boards retain their separate material. The grain repeats at a consistent length scale with high roughness. The static snapshot is regenerated and rebaked with this material. The albedo is an artistic candidate, not a calibrated normal/roughness scan.

## Thatch silhouette volume

The roof shape study and actual-Enshrouded target now guide an underside and closed gable/eave skirts, with approximately 20cm of irregular thatch thickness. Top and lower edge samples share the same contour. This is cosmetic mesh volume; collision remains unchanged and the rafters meet the lower thatch surface. The source and static snapshot are regenerated together.

## Foliage atlas trial and grounding

The original tree01 atlas is 128px. A generated 1254px RGBA replacement is applied to that variant only, preserving existing UV geometry and alpha-scissor/coverage settings. Matched actual captures compare original and replacement at the same camera; bark and leaf detail improve, but the low-detail mesh and remaining original variants still limit quality. The initial TreePack ring now samples the actual surrounding landscape triangles rather than keeping a fixed height. The snapshot is regenerated for those positions; runtime atlas substitution remains separate from its static lightmaps.
