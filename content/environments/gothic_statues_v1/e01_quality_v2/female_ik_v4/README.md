# Existing female game rig: E01 pose guide

Uses `content/characters/quaternius/Superhero_Female_FullBody.gltf` and its existing 65-bone skeleton. Source license: CC0-1.0, Quaternius Universal Base Characters [Standard]; see the original character folder's license and provenance. The source character files are unchanged. Hip, glute and chest proportions are the mesh itself, with no added alignment spheres.

`female_ik_pose.blend` retains the posed skeleton. `female_ik_pose.glb` is a static evaluated-mesh export with the same pose. Four 900 × 900 RGBA PNGs show it from cameras separated by 90 degrees, with identical orthographic scale, target and 20-degree elevation. They need no matting. `four_views.png` adds labels and a neutral background for review only; use the separate transparent files for conditioning.

This is a pose guide, not the finished classical statue. The source model has a stylized face and no hair or tunic. It provides coherent anatomy and silhouettes for the next art pass. It is also a usable starting mesh, avoiding reconstruction of a body we already possess. The GLB has not been placed into a dungeon or visually approved as final art.

Edit `pose_controls.json`, then run from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python content/environments/gothic_statues_v1/e01_quality_v2/female_ik_guide.py
```

Controls use Blender world metres: Z up, +Y forward, left limbs on -X. Ankle targets are world positions; the reaching wrist is an offset from its shoulder, while the supporting wrist has a world height. Pole targets set elbow and knee bend directions. The analytic two-bone solver preserves native segment lengths, rejects unreachable targets and restricts knees to 90–155 degrees and elbows to 5–150 degrees for this crawl. A final whole-pose vertical offset places the lowest skin point on the floor. These are crawl-specific limits, not a complete biomechanical joint model.

`ik_checks.json` records target residuals, bone lengths, knee/elbow bends and the supporting skin clearances before subdivision. The latter are samples of the weighted skin regions, not collision or self-intersection proof. The build asserts residuals below 1 mm, length changes below 0.1 mm, no negative regional floor clearance, and contact gaps below 25 mm. `cameras.json` records actual camera transforms and projection; orthographic views are not perspective-calibrated inputs for a model with fixed perspective intrinsics.

The local review HTML uses the existing Shape Studio model-viewer bundle at `/static/vendor/model-viewer.min.js`. Serve this directory at `http://127.0.0.1:7865/static/e01-ik-review/` without changing the generator UI or a user's job state.
