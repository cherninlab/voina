# Hooded cultist — standalone raider outfit

The existing Quaternius male raider is preserved underneath a full pointed hood,
linen robe, shoulder cowl, bell sleeves and rope belt. His whole body, legs and
feet included, hands, face, textures and 65-bone rest skeleton remain intact. The
clothing binds to that same skeleton plus 34 robe bones added under it: the skirt
hangs from 8 chains of 4 bones under the pelvis and each bell sleeve from a droop
bone on the forearm, which the game simulates as heavy linen (below). The village
raiders wear it (`docs/mobs.md`).

## Robe cloth (T-110)

The robe hangs to the feet, tents round the legs so no leg shows through it, and
falls loose when a cultist dies or is cut in half. `gameplay/mobs/robe_cloth.gd`
(`RobeCloth`) adds skeleton modifiers to the cultist's body in `MobVisual`, and the
garments draw with `content/mobs/hooded_cultist/robe_push.gdshader`, which keeps the
imported linen, seam, lining and rope looks. All of it is cosmetic: it runs on every
peer from the pose the host's state and RPCs already drive, and nothing new is
replicated. The skirt hangs from 8 chains of 4 bones under the pelvis, and each bell
sleeve from a droop bone on the forearm.

Standing, nothing is simulated. **Gait**, first of all the modifiers, shortens the
stride to 72 percent of the clip's swing, as a robe hobbles it (foot planting still
runs after it). **Push**, last, writes this frame's hips, knees, ankles, elbows and
hands into the garments' instance uniforms. The shared shader code
(`content/mobs/hooded_cultist/robe_shape.gdshaderinc`) moves each skirt vertex out, in
its own direction from the hips, to the farthest point of the legs at or above its
height (wider where a leg slants) plus 4.5 cm, sloping in a little as it falls. The
robe tents over a forward knee and stretches straight between the legs, and a leg
cannot get outside it. A hand swinging past the hip presses a dent into the cloth.

A death or a bisect calls `RobeCloth.drape`: gait off, the engine's
`SpringBoneSimulator3D` and **Stride** (the chains following the thighs at 85
percent) start after the ragdoll's simulator, the chains go slack and heavy and fall
along the legs onto a ground plane where a ray from the body hits the floor, and the
shader only pushes the cloth out of capsules round the legs. The hem reaches the ground
and stops moving on the body within about two seconds. Each cut half gets its own
draped robe, the cut edge hanging free; `gameplay/mobs/mob_cut.gdshader` includes the
same shader code, so the legs stay inside a half's robe too, and it shades the robe's
inside as cloth rather than flesh. `MobVisual.bisect` puts the imported materials back
before the cut is baked, so the halves keep the linen's texture. A dead body lying with
its knees up is not covered: the cloth lies along and beside its legs, without
clipping.

Earlier versions simulated the live robe (spring bones, then a GDScript pass pushing the
bones out of the legs). They cost up to 0.3 ms per cultist and still let a striding leg
out between their sample points, or left it outside a lagging hem.

### Cost

Measured headless on the Apple M2 Mac:

- Standing, per cultist: Gait and Push (four bone rotations, ten bone reads, eleven
  uniform writes) on the CPU, and the tent's few segment tests per robe vertex on the
  GPU. `MobVisual.cache_pose` skips the skirt bones.
- Loading the cultist model takes about 0.4 s. `MobVisual` starts it on a worker
  thread as soon as the mob scripts load, so it is normally ready before the first
  village raider spawns; each later spawn takes about 0.5 ms.
- A bisect bakes the cut into every vertex in script: 69 ms for a cultist (43 ms of it
  the bake, 13,400 garment and 7,300 body vertices), against 26 ms for a plain raider.
  The garments were thinned for this (gown 48 sides, hood 40 by 22, cowl 40, sleeves 24,
  a 96-segment rope); the bake uses the transpose of each blended bone basis rather than
  its inverse.

## Open and use

- `content/mobs/hooded_cultist/source/hooded_cultist.blend`: editable Blender source,
  separate human and garment meshes, original skeleton, inspection actions and studio.
  Select `Armature` and enter Pose Mode to pose the character. The source folder
  has `.gdignore`, so Godot does not import the Blender file.
- `content/mobs/hooded_cultist/hooded_cultist.glb`: self-contained export with the
  three original human meshes and one consolidated garment mesh, sharing the rig.
- `content/mobs/hooded_cultist/hooded_cultist.tscn`: visual-only Godot wrapper,
  facing -Z, with the existing `content/animations/quaternius/male.res` library.
  Open it in the editor and use its AnimationPlayer to inspect Idle, Walk,
  Jog_Fwd, Punch_Jab and the other existing clips. It has no gameplay script.
- `content/mobs/hooded_cultist/previews/cultist_beauty.png`: Blender studio render.
- `content/mobs/hooded_cultist/previews/cultist_godot.png`: isolated Godot
  Mobile/Metal render using the existing Idle clip, without a gameplay arena.
- `content/mobs/hooded_cultist/model_stats.json`: measured geometry and bone counts.

The original human remains about 1.8 m tall; the hood reaches about 2.16 m.
Coordinates use metres and feet at the origin. The raw glTF faces +Z; the wrapper
rotates it 180 degrees. No physics shapes or nonuniform body scaling are added.

## Animation and limitations

The runtime wrapper reuses the existing male animation library without editing
it. All 65 bone names and rest transforms are checked against the original model.
The gown blends pelvis and thigh weights, sleeves follow the spine and arms, and
the hood follows the neck and head. All vertices have at most four influences.

Blender includes three separate FK inspection actions: cultist_idle,
cultist_shamble_preview and cultist_reach_preview. These are authoring previews;
the Godot wrapper uses the existing raider clips instead. Source actions are also
stored in muted NLA tracks so they do not all layer at once.

The gown has a ring every 4 cm below the hips, one on each skirt joint, and only
shallow sculpted folds there, so it bends smoothly on the chains; deep baked folds
crushed when the chains bent. The robe cloth above is the game's (`MobVisual`);
this wrapper scene has none of it.

## Provenance

The human and its textures retain the existing CC0 1.0 license at
`content/characters/quaternius/License_Standard.txt`. Existing animations retain
the license at `content/animations/quaternius/License.txt`. Garments, linen maps
and inspection poses are original project work. The supplied reference image is
not redistributed. Full source information is in the asset's `provenance.json`.

## Rebuild and check

Built with Blender 5.2.2 LTS. Run from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python scripts/art/build_hooded_cultist.py -- --no-render
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --quit-after 5 \
  --script content/mobs/hooded_cultist/validate_cultist.gd
python3 scripts/smoke_test.py "$GODOT"
```

Omit `-- --no-render` to rebuild studio previews too. Rebuilding overwrites the
source/export; save manual Blender edits under another name first. The asset check
verifies original bone rest transforms, the 34 robe bones and their parents, the whole
original body, skin weights, existing animation playback and finite sampled bone
transforms. `tests/robe_cloth_test.tscn` (run by `scripts/mob_smoke_test.py`) checks
the robe: nothing simulated while standing, every garment surface on the robe shader, the
shader's joints matching this frame's legs through a jog, the shader's tent (done again on
the CPU for points all round the skirt) keeping it outside the legs, the hem hanging down
to the feet, and the robe draping on the ground and settling within two seconds
after a death and after a bisect, with ragdolls and caps intact. Inspect logs for
assertion/errors even if Godot exits zero. Camera/input and two-Mac Tailscale tests
are separate and were not performed for this art-only change.

GLB, PNG and the Blender source use Git LFS. Run `git lfs pull` after cloning.
