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

## Original near-village broadleaf geometry

Tree01 instances within 80m of village origin now use an original bent/tapered trunk, 14 two-segment branches, and overlapping curved foliage cards. The generated shape sheet is paired with the existing atlas; bark and leaf UVs use their separate islands. Instances share mesh resources, vary rotation, reuse original placement, and scale proportionally to original tree height. They are cosmetic with no collision. Far instances retain the original lightweight geometry. This is spatial selection around the village, not a measured camera LOD system or M2 performance result. Other tree variants still use the old assets.

## Height and aerial atmosphere

A shared atmosphere function applies native exponential fog with a low height component, restrained aerial perspective and directional sun scattering. It is applied after the baked snapshot loads and in the source builder, so fog adjustments do not require repacking geometry. ACES exposure, the sky image and the wide-angle shader remain unchanged. Actual captures check foreground readability against distant separation. This is non-volumetric Mobile fog, not Enshrouded-style volumetric lighting or measured M2 acceptance.
# Player projection calibration

Art captures now copy the live owner's camera FOV and assert that it matches the retained wide-angle pass's source projection. Earlier art captures used 68 degrees while the default player/lens source uses 108 degrees. Those images remain real runtime renders and their collision checks remain valid, but their framing was not calibrated to the player's projection. Mik's shader and wrapper are unchanged.

The `runtime-matched-projection` three-view capture passed floor/ramp rays, four player landing checks and the new projection assertion. Peripheral stretching remains visible; this change does not establish a fix for gameplay temporal flicker or camera feel. The new `target-player-projection.png` is an AI visual target conditioned on this calibrated capture and the supplied actual Enshrouded screenshots, not gameplay evidence.


## Mineral-earth ground pass

The source builder and baked scene now share the terrain-material factory. Runtime replaces only the snapshot terrain material identified by its dirt texture uniform, preserving mesh UV2, LightmapGI bindings and collision. A mipmapped mineral-earth base color blends with the existing soil at a second scale; smooth low-frequency coordinate warping and earth-tone modulation reduce uniform repetition. Grass/paving masks and their normals remain unchanged. The calibrated three-view Metal capture in `runtime-mineral-ground` passes floor/ramp rays, four player landing drops and the 108-degree lens-source assertion. This improves surface variation, not geometric ground relief or temporal antialiasing.

## Nearby broadleaf variants

The original branching-tree replacement now covers tree01, tree02, tree03, tree04, tree08 and tree09 within 80 metres of village origin. Source bounds determine crown width; six restrained leaf tints preserve some species variation. Conifers, other species and distant meshes retain their original geometry. This reuses the paired `broadleaf-shape-study.png` and `tree01_atlas.png`, without new external assets. `runtime-broadleaf-variety` contains three calibrated Metal views; floor/ramp, four landing checks and projection assertion pass. This is a spatial asset selection, not dynamic LOD or measured M2 performance.

## Grouped woodland edge

A deterministic 52-group placement pass adds 345 smaller broadleaf trees between 43 and 126 metres from village origin, rejecting the village footprint, central approach corridor and steep terrain samples. Bases use the actual landscape triangle interpolation. The existing original tree mesh and generated atlas are reused through two MultiMesh batches with varied size, orientation and leaf color, rather than hundreds of independent tree nodes. The new groups are cosmetic and add no collision. They receive realtime sun/sky lighting, without dynamic lightmap-probe sampling for the whole batch. Source-builder bake preparation skips this live layer.

Three Metal views are saved in `runtime-woodland-daylight`; floor/ramp rays, four player drops and owner/lens projection checks pass. The first dark-tint trial was replaced after capture review. This is not a measured framerate or thermal claim. Old distant tree cards, smooth distant terrain and lens-edge stretching remain visible.

## Landscape material blending

The source builder and loaded snapshot share a landscape-material factory. Slope and lower elevation now reveal schist in irregular warped patches, with restrained strata and wider grass-color variation. This reuses the paired schist target/texture; no terrain vertices, tree bases or collision changed. Three calibrated Metal captures are in `runtime-rocky-slopes`; floor/ramp rays, four player landings, projection assertion, editor import and local networking smoke pass. The visual change is modest under current atmospheric lighting. Distant silhouettes are still smooth and need actual geometry work; material blending alone does not meet the reference target.

## Fractured ridge silhouettes

Ten high, separated terrain crest sites now receive original terrain-conforming shoulder meshes. Each 20-by-8 patch follows the sampled landscape, with an asymmetric rock envelope, stepped fracture heights and buried perimeter, using the shared triplanar schist material. This changes the skyline without moving the underlying terrain or existing plants. The meshes are distant cosmetic scenery and add no collision. Bake preparation skips the live layer.

The generated `ridge-shape-study.png` provides approximate front, side and plan views paired with `schist_rock.png`; it remains a target rather than exact implemented CAD. Initial imported-boulder assemblies were rejected because exposed overhangs and excessive burial failed to give a useful result. `runtime-fractured-ridges` contains the final three calibrated Metal views. Floor/ramp rays, four real-player landings and projection checks pass. Further geological shaping, terrain detail and temporal rendering work remain.

Ridge follow-up: four piecewise asymmetric crest profiles replace the shared sinusoidal mound. Wider, lower shoulders and diagonal cross-sections reduce repeated spike outlines. The final `runtime-varied-crests` views retain all floor/ramp, player landing and projection checks. This is still a distant silhouette pass; the original smooth mountain base remains visible.

## Northern approach and outer ground

The visible 576-by-576-metre landscape now receives Jolt triangle collision from its exact mesh, including when the old baked snapshot is loaded. The village palisade has a six-metre opening on the northern segment. Split wall pieces keep collision on either side; decorative uprights are cleared through the opening. A small terrain-matched apron blends the village floor down to the outer landscape, with matching collision. The source builder includes the opening during future bake preparation; a saved metadata flag avoids applying it twice to newly prepared snapshots.

The real-world capture check sweeps the actual player collision shape through the gate, checks 21 continuous ground samples along the apron, and drops the real player at four inner and four outer locations. All passed in `runtime-north-shipped` (four views, including the gate approach), alongside the floor/ramp and 108-degree lens-source checks. Outer test points are north z=-40, east x=50, west x=-60 and south z=60. This proves those locations and approach clearance, not exhaustive navigation of the entire landscape or two-machine acceptance. Outer decorative vegetation and rock dressing remain cosmetic. The terrain ends at its finite mesh boundary; this is not an infinite world.

## Timber entrance target

The new `target-north-entrance.png` uses the actual northern approach camera and supplied Enshrouded screenshot as references. It pairs existing aged timber, mineral earth and groundcover studies with the entrance geometry. The timber frame uses two colliding posts, a colliding lintel and inward diagonal braces; the passage stays open. Frame metadata preserves it across future bake preparation without duplication. Dense ferns, more natural path dressing and the target lighting remain unfinished. This generated image is a target, not game evidence.

The final frame uses one shared lintel height over uneven ground: post lengths adapt to their bases, while both braces meet below the lintel. An initial high brace was corrected after close-camera review. `runtime-gate-supported` contains four real Metal views; actual player-shape clearance, 21 apron samples, eight landings and lens-source checks pass.

## Opaque fern border

The entrance target now has an original fern shape study and a live opaque mesh implementation: eight arching fronds, continuous rachis strips and paired folded leaflets. One MultiMesh places 127 varied clumps along northern wall edges, excluding an eight-metre strip around the gate axis. They have no collision and remain outside the static bake. Colors use a rough olive shader with restrained backlighting; no alpha cards or imported plant meshes are added.

Close-camera review prompted connected stems, wider leaves and a less saturated material. Native mesh inspection caught reversed winding; mean normal Y changed from -0.912 to +0.912 after correction. `runtime-ferns-lit` records four real Metal views with gate clearance, 21 apron rays, eight landings and projection checks passing. The plants remain a simplified interpretation of the generated study; target lighting, richer ground transitions and temporal rendering still need work. No M2 cost claim is made.

## Explicit sky/ambient balance and refreshed bake

Matched capture trials isolated height fog, all fog, contrast 1.12 and ambient energy 0.24. Height-fog removal had little effect on the near wall; removing all fog mostly clarified distant terrain. The contrast trial brightened clouds too much and was rejected. Ambient-energy-only adjustment produced identical sampled foreground pixels because sky contribution was still 1.0. Godot documents that ambient energy is ineffective at full sky contribution: [Environment reference](https://docs.godotengine.org/en/latest/classes/class_environment.html#class-environment-property-ambient-light-sky-contribution).

The retained profile explicitly uses sky contribution 0.65, ambient color 53657b and ambient energy 0.4. Sun direction/energy, exposure, ACES, fog and protected lens remain unchanged. Static geometry was regenerated and the native Metal lightmap bake refreshed: 488 UV2 meshes; editor reported completed bake in 1.70 seconds. The saved scene includes the current open entrance, apron and timber frame. Temporary editor resource-busy warnings did not recur in the subsequent clean import or runtime checks.

`runtime-skyfill-baked` contains four calibrated real captures. The gate and ramp remain readable without the rejected contrast grade. Gate capsule, 21 apron samples, eight inner/outer player landings and projection checks pass. This is an incremental balance improvement; it does not establish Enshrouded-level lighting, M2 performance or temporal stability.

## Winding northern woodland trail

The terrain shader now blends mineral earth into a winding strip from the gate approach toward z=-112, with varying width, noisy shoulders and a fading end. Its center follows the same function used by placement clearance and checks. Two existing tree/bush meshes are hidden from the corridor before nearby-tree replacement; sapling placement also excludes it. The original village grass mesh/material is reused in a live MultiMesh along the shoulders, with patchy placement, tapered density from seven to thirteen metres off the centerline, and no collision. The final pass places 3,156 clumps. No new external assets or terrain heights are introduced.

A fifth calibrated camera records the actual trail. The generated `target-woodland-trail.png` is conditioned on that view and the supplied Enshrouded image, paired with mineral-earth/schist/tree textures and existing grass, fern, broadleaf and ridge shape studies. It is a target, not gameplay evidence.

Checks now include 13 route samples matching terrain collision within 5cm and sampled normals above 0.71 Y, plus two extra real-player drops at z=-70 and z=-100 (ten drops total). Gate clearance, 21 apron samples and existing floor/ramp/projection checks remain. These samples do not prove exhaustive navigation or M2 performance. Tree cards, peripheral lens stretching, geological detail and broader vegetation remain below reference.

The final five-view capture set is `runtime-trail-taper`; all route, approach and player-landing checks pass. The extra field view deliberately retains the real wide-angle output, including its known peripheral artifacts, for an honest target comparison.

## Broader branching foliage and autumn atlas

Atlas inspection identified 31 broadleaf variants among the 36 original tree species. Nearby replacement now covers all 31 within the existing 80-metre radius, retaining the five conifer variants and the lower-detail distant meshes. It reuses the shared original WoodlandTree trunk, branches and curved foliage geometry; crown width, uniform height, deterministic yaw and species tint remain varied. Nine autumn variants use a new ImageGen copper/ochre atlas with documented prompt, transparent cutouts, VRAM compression and mipmaps, paired with the woodland trail target. This preserves seasonal color instead of tinting green leaves brown. The trees remain cosmetic and are not botanical reconstructions of every original species.

`runtime-autumn-canopies` contains five actual Metal captures. Import, ten player landings, 13 trail samples, 21 apron samples, gate capsule clearance, floor/ramp checks, protected-lens projection and local two-process networking checks pass. Mik's lens and wrapper are unchanged. Sparse groundcover, distant card trees, simple geology and known peripheral lens stretching remain visible; this pass does not establish target fidelity, temporal stability or M2 performance.

## Irregular mature woodland stands

The matched `target-woodland-stands.png` uses the actual autumn trail view and supplied Enshrouded garden screenshot. Its manifest pairs the existing green/autumn atlases, mineral earth and schist materials with broadleaf, grass and fern shape studies. It remains an approximate generated target, not game evidence.

The live trail now has 36 additional mature trees in irregular groups, with three-metre minimum separation among new trunks, varied height (7.5–16m) and crown width, slope rejection, and a five-metre centerline exclusion. These reuse the existing two tree MultiMesh batches (381 total saplings/mature trees). An initial 72-tree pass looked like rows and was rejected after capture. Shoulder grass rises from 3,156 to 12,667 clumps in the existing batch, retaining patch noise, outer density taper and the 5.6m clear center strip. All added vegetation is cosmetic; no terrain or collision changes.

`runtime-irregular-stands` contains the final five real Metal views. Headless import, local ENet/disconnect checks, ten player landings, 13 trail samples, 21 apron samples, gate capsule, floor/ramp and lens-projection checks pass. The protected shader/wrapper and rendering profile are unchanged. Broader crown structure, richer understory, distant foliage, geology and rendering still fall short of target. Added GPU cost on M2 has not been measured.

## Spreading broadleaf crowns and bough atlases

The earlier atlas mapped an entire pointed tree silhouette onto each leaf card. Two new ImageGen bough atlases (green and autumn) retain the left bark UV region but replace the right silhouette with an irregular oak branch cluster. Both are transparent, mipmapped VRAM-compressed artistic basecolor candidates, paired with `target-woodland-stands.png` and documented in `oak_bough_atlas-prompt.md`. Only the original branching WoodlandTree mesh uses them; distant original imported tree meshes keep their original tree atlases.

The shared original mesh now uses 12 spreading primary branches with two lateral forks each, shorter/wider leaf clusters and three crown leaders rather than a narrow upright cone. Leaf normals are artist-shaped around the crown to soften flat-card shading; they are not scanned leaf normals. The mesh is shared by nearby replacements and the two instanced woodland batches. No physics shapes, placements or protected lens files change.

`runtime-rounded-normals` contains the final five native Metal views. Import, ten player drops, 13 trail samples, 21 apron samples, gate capsule clearance, floor/ramp/projection checks and local ENet/disconnect smoke pass. Crowns read broader in the matched trail/gate cameras, but repeated leaf-card boundaries, distant trees, understory, terrain geology and rendering remain below the target. Temporal quality and M2 cost remain unmeasured.

## Woodland fern understory

`understory-placement-study.png` combines the actual trail composition with the original fern shape reference, plus approximate overhead and side planting views. The manifest pairs it with existing terrain/tree materials and original fern/grass geometry. It is generated guidance, not gameplay or an exact orthographic plan.

The existing fern MultiMesh now includes 464 additional woodland clumps (591 with the wall border), placed in deterministic noise patches from z=-37 to -107 with varied uniform scale. Centers stay at least 4.2m from the trail center; one-metre slope samples reject steep placements. All plants remain cosmetic and reuse the existing opaque mesh/material batch. Close capture caught overly diamond-shaped leaflets: eight-point curved outlines replace the four-point outlines. Per-leaf UVs add restrained midrib, vein and color variation procedurally, with fine veins fading using the pixel footprint. No alpha texture, extra texture sampling or new external assets.

Final five-view evidence is `runtime-veined-understory`. Headless import, local two-process ENet/disconnect, ten actual player landings, 13 trail samples, 21 apron samples, gate clearance and floor/ramp/lens-projection checks pass. Mik's lens and wrapper remain unchanged. Plants are still simplified; ground transition variety, lighting, distant foliage and temporal fidelity remain below the reference. No M2 GPU-cost or human input acceptance claim.

## Grim village reference pass

The live source and loaded baked snapshot both receive the same cosmetic `AshenVillage` dressing (bake preparation skips it). It changes materials, storm sky and distance atmosphere, adds emissive framed facade windows placed using wall collision rays, and adds iron market/house lantern fixtures with small warm light pools. Structural timber uses existing matching Valhalla WoodPlanksFlat basecolor/normal/roughness textures; dirt blending is quieter and high-roughness. Original physics bodies and collision shapes are untouched. The default lit preset detaches daylight GI, as for the other lighting presets; no stale daylight rebake is claimed.

Real Mobile/Metal captures and import/combat/network checks accompany this pass. The selected generated target remains a visual guide: existing cottage/tree geometry and terrain silhouettes are retained, so this is not an exact reproduction or a performance acceptance result.

## Threatening distant ridges

The distant cosmetic ridge overlays have taller narrower fractured crests. Mountain slopes use existing Valhalla StoneGeneric basecolor, matching roughness and triplanar normal detail, with cooler dark rock, stronger irregular strata and greater bare-rock coverage at elevation. This replaces the pale generated schist on the surrounding landscape material. The north trail material and all terrain/collision height sampling stay unchanged; the crest overlays are cosmetic and distant. Existing Valhalla provenance applies; no external assets were added.
