# Hooded cultist — standalone raider outfit

The existing Quaternius male raider is preserved underneath a full pointed hood,
linen robe, shoulder cowl, bell sleeves and rope belt. His body from the hips up,
hands, face, textures and 65-bone rest skeleton remain intact; the legs and feet
the gown covers are removed (`LEG_HIDE` in the build script: every face below
0.95 m in the rest pose), because a jogging leg swings out through the stiff gown
and a foot left below the hem floats ahead of it. The cultist glides. The gown's
hem follows the thighs by at most 30 percent, so it sways without tearing open.
The clothing binds to that same skeleton. The village raiders wear it
(`docs/mobs.md`).

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

Cloth is skinned, not simulated. Extreme poses may need garment weight/shape
polish. Gameplay combat, ragdoll/bisect behavior and runtime performance have not
been validated for the outfit; none are enabled here.

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
verifies original bone rest transforms, the human's height and arm span, skin weights,
existing animation playback and finite sampled bone transforms. Inspect logs for
assertion/errors even if Godot exits zero. Camera/input and two-Mac Tailscale tests
are separate and were not performed for this art-only change.

GLB, PNG and the Blender source use Git LFS. Run `git lfs pull` after cloning.
