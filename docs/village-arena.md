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

The generated groundcover study is paired with solid, three-segment tapered grass strips in `green_borders()`. Generated alpha cards were rejected for fringes and clipped silhouettes. Geometry needs no transparency sorting or alpha edge filtering. The experimental static lightmap snapshot is not enabled: probe data is empty and the actual capture does not yet justify replacing the procedural level.

## Surrounding landscape material pass

Original generated schist replaces the paving texture on distant exposed terrain. Triplanar mapping avoids vertical stretch, broad color variation breaks repetition, and the surrounding visual terrain uses a 3m sampling grid. Rock shelves are distributed across the slopes instead of a ring; 320 trees occupy the surrounding land. These outer visuals do not expand the playable collision boundary. No M2 performance acceptance is implied.

## Ridge silhouette pass

The paired schist-valley target guides domain-warped ridges, smaller crags and softened rock strata in the distant height field. Vegetation and rock placements still interpolate the exact rendered triangles. The playable terrain height and collision remain independent.
