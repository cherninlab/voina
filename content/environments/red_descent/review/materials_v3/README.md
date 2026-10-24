# Dungeon material review — 2026-10-24

`before/` and `after/` contain eight actual Godot 4.7.2 Mobile/Metal frames at 1440×900. Both runs use masonry revision `9c42bd9`, game-source fingerprint `218e4a846908`, the same cameras and Natural presentation, and the unchanged caller densities (`stone`/`wall`: 0.22). `before/` uses the original shader; `after/` uses the shader recorded in `identity.json`. Torch flicker is live, so the images are not a pixel-difference benchmark. None is an ImageGen result.

The shader keeps the existing parameter names and original CC0 texture files. It changes only the material response:

- Broad weathering and medium surface variation use metre-based coordinates independently of the fine maps. Plaster loss forms larger worn areas, with the existing peel mask contributing edge variation.
- The plaster tint applies to the coat before blending. Exposed masonry retains its mineral colour, including under red plaster. Its separate projection is 0.16/0.32 repeats per metre.
- Dry roughness retains the scan's variation instead of flattening everything below a minimum. Dampness is sparse and localized; algae no longer supplies a green wash across unrelated materials.
- Timber samples a different part of the same oak scan per instance, with restrained value variation, less saturated orange, and weaker fine normals.
- OpenGL normal Y follows the actual negative-V projection axis. Existing height relief is capped at 4 mm for timber / 12 mm for minerals and fades with distance and grazing view angle. It changes no silhouette or collision.

## Verification and reproduction

`validation/editor-after.txt` records a clean headless editor import. `validation/smoke.txt` records the main smoke suite, including combat and the local ENet pair. `validation/capture-before.txt` and `capture-after.txt` record all eight nonblank frames and the Mobile/Metal device. There are no script or shader errors. Both captures retain the pre-existing seven Texture RID / one ObjectDB shutdown warnings; the smoke process retains its ObjectDB shutdown warning.

The scoped `capture_materials.gd` is a copy of `scripts/capture_dungeon.gd` with one behavior change: `RenderingServer.force_draw()` replaces waiting for `frame_post_draw` immediately before reading the viewport. A background run stalled after view 03 for several minutes, then recovered and completed; its full log is retained as `capture-before-natural-draw.txt`. The shared capture script was not edited. All windowed runs used `scripts/godot_bg.sh`; no window focus changes were made.

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
GODOT="$GODOT" scripts/godot_bg.sh --path . --script content/environments/red_descent/review/materials_v3/capture_materials.gd -- --dungeon --shading-ephemeral --capture-dir=/tmp/material-review
```

`identity.json` records shader/capture hashes and unchanged uniform names. `shader.patch.txt` preserves the exact shader diff. A private `board.py sync` used `rebase --autostash`, reported success, but left the local shader in autostash `ddfe6f85f6a0ad8d1bab24cf61e850bc138f07fb` and restored the baseline file. The saved shader was recovered byte-for-byte before the final refinement; no stash entry was applied or dropped. This tooling behavior remains a separate investigation.

## Limits and integration

This is a material improvement, not final art acceptance. At the retained 0.22 density, broad masonry still reads as repeated small blocks. Integration should review the proposed 0.16 stone/wall density beside the substrate projection; this is an art-scale choice, not the source scan's documented physical scale. The final shaped masonry revision `92f1ad7` and the separate wooden-bridge replacement are outside this matched pair.

The rejected bridge's repeated ridges and gaps remain geometric artifacts. The shader does not hide them. Broad wall silhouettes, repeated openings, flat plaster geometry and lighting still limit resemblance to the art reference. No geometry, collision, light, generated model, source bitmap or bridge asset was edited by this workstream. Capture frame intervals are retained for diagnosis only; no gameplay performance, manual camera/input, two-Mac or Tailscale acceptance is claimed.
