# Using the Universal Base Characters pack

The supplied **Universal Base Characters [Standard]** archive by Quaternius is integrated. Its bundled license states **CC0 1.0**; the original license is preserved at `content/characters/quaternius/License_Standard.txt`. Archive and source hashes, included files and import corrections are recorded in `provenance.json` beside it.

## Use it now

1. Install Git LFS, then clone/pull `cherninlab/voina` and run `git lfs pull`. PNG textures and binary mesh buffers use LFS; a normal Git checkout without LFS content cannot import them.
2. Open `project.godot` in Godot 4.7.2 Standard. Allow the first asset import to finish.
3. Press F5 and choose Host or Join. The host uses the male model, joining players use the female model. Movement, capsule collision and combat remain controlled by the existing player scripts.
4. Press V to switch cameras. The local first-person character is hidden while its shadow remains; remote characters stay visible.

To inspect/reuse a model in the editor, open `content/characters/quaternius/male.tscn` or `female.tscn` in the 3D viewport, or drag the scene into another scene. The wrapper assumes the player's origin is at capsule center, so it places the feet 0.9 m below the root and rotates the source model 180 degrees to face the game's -Z direction. The source models are approximately 1.8 m tall; physics shape dimensions are unchanged.

## What is included

Both full-body glTF models, their .bin buffers and referenced textures are included (about 30 MiB before Git LFS). Each imported skeleton has **65 bones**, including `pelvis`, `spine_01`–`spine_03`, `Head`, `upperarm_l/r` and hand/finger bones. The Standard character archive has **no animation clips**. The separately supplied Universal Animation Library now supplies retargeted idle, movement, jump and combat clips. See [animation integration and usage](animations-and-environments.md). A static relaxed arm pose remains a fallback when no animation library is assigned.

The original archive also contains alternate engine exports, hairstyle variants, duplicate textures and a preview image. Those are left in the original local ZIP rather than duplicated in the runtime project. Reimporting the included glTF files does not require that ZIP.

Two broken texture URI aliases in the original glTF files were corrected to the matching supplied filenames: `T_Eye_Normal_png.png` → `T_Eye_Normal.png` and `T_Hair_1_Normal_png.png` → `T_Hair_1_Normal.png`. No texture pixels or geometry were changed.

## Animation integration

Both wrapper scenes now reference generated per-character AnimationLibrary resources. The reproducible retarget build script, clip mappings and extension instructions are documented in [animations and environments](animations-and-environments.md). Animation remains cosmetic; gameplay movement and combat stay in their existing controllers.

## Check

Run the normal import and multiplayer checks from README, plus:

```sh
"$GODOT" --headless --path . --script tests/character_test.gd
```

This checks both imports, skeletons, idle pose and first-person shadow flags. Visible checks on the development Mac confirmed the male model's materials, facing and retargeted idle pose. Two-Mac play and final animation quality remain manual acceptance work.
