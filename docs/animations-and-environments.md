# Animation and modular environment packs

Both user-supplied packs are integrated. Run `git lfs pull` before opening the project in Godot 4.7.2 Standard. Their bundled CC0 license files and archive/source hashes are retained alongside each pack.

## Universal Animation Library [Standard] — Quaternius

`content/animations/quaternius/UAL1_Standard.glb` is the supplied **in-place** Unreal/Godot export. It contains 43 source clips. The `_RM` export and other engine formats remain in the original local ZIP, because gameplay movement is controlled by CharacterBody3D rather than animation root motion.

Nine clips are retargeted to **each** male/female base character in `male.res` and `female.res`:

| Game state | Clip |
| --- | --- |
| Idle | Idle |
| Movement | Jog_Fwd |
| Airborne | Jump |
| Melee | Punch_Jab |
| Beam | Pistol_Shoot |
| Block | Sword_Idle (temporary guard-ready pose) |
| Dash | Sprint (temporary dash visual) |
| Stagger | Hit_Chest |
| Available for tuning | Walk |

Godot strips the source `_Loop` suffix on import; these are the actual imported names. CharacterVisual drives one AnimationPlayer with short crossfades. Attack animation playback is triggered by the existing host-approved effect RPC; replicated phase/state chooses stagger, block and dash. Damage timing, stamina, physics, player ownership and hit detection remain in the gameplay controller.

These are **full-body** clips. Upper-body layering, backward/strafe-specific motion, weapons/viewmodels, pitch aiming, exact frame-to-contact alignment and polished dash/guard animations remain work to do. Block reuses a sword-ready clip and dash reuses sprint; those clips are not authored block/dodge animations. Remote airborne state currently uses replicated vertical velocity. Two-Mac latency and human motion review remain manual acceptance gates.

### Rebuild or extend the clips

The skeleton names match, but their rest poses/proportions differ. The build script samples the source `A_TPose` reference, maps every track by bone name, converts rotations between the reference bases, preserves the target bone lengths, and scales pelvis offsets to each character's height. Root translation/scale tracks are removed; the controller owns displacement. The animation import keeps immutable tracks so reference bone rotations are available.

```sh
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --script scripts/build_character_animations.gd
```

To use another source clip, add its imported name to `CLIPS` in that script (and to `LOOPS` if appropriate), rebuild both libraries, then map it in `gameplay/player/character_visual.gd`. The full original source library stays available for inspection. Do not let cosmetic clip selection decide damage or network authority.

## Free 3D Modular Game Assets For Prototyping — Rgsdev

`content/environments/rgsdev/` contains all **81 FBX assets**, the palette texture, license and provenance. These include 75 individual pieces, five sample layouts, and the sample character. Website shortcut files from the ZIP are omitted. The source FBX files are unchanged.

The FBX files reference `aap color palette.png`, while the ZIP supplies `texture.png`. Exact copies of that supplied image are placed under the referenced filename in each FBX folder. This resolves materials during native Godot FBX import; no Blender conversion is needed for this project.

The current arena includes two boxes, one pillar and stairs near its perimeter, in addition to the existing greybox floor, walls and cover.

### Place more pieces

1. Drag `gameplay/prototype_prop.tscn` into a scene.
2. Select its root and choose any imported piece in the **Model Scene** field.
3. Move/rotate the root. Keep its scale uniform; use duplicate pieces or alter a mesh outside the physics body for different dimensions.
4. Keep **Collision Enabled** checked for static arena cover; turn it off for decorative pieces.

The reusable wrapper centers the imported geometry and puts its base on local Y=0, because the source files retain the author's original scene offsets. It generates static triangle-mesh collision. Do not use these generated static bodies as dynamic rigid-body props. The sample layouts can also be opened directly in Godot's 3D viewport.

## Verify

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
```

The smoke command includes asset checks: nine clips for both rigs, all tracks bound to real bones, actual bone movement, imported prop scale and static collision, followed by combat and two-process ENet checks. Both source packs and generated `.res` libraries use Git LFS; CI checks out LFS objects before import.
