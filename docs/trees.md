# Tree pack 1.1

Task: T-009, owned and shipped by `theo-codex-1`.

## Included and attached

The user-supplied `tree_pack_1.1.zip` is imported under `content/environments/tree_pack/`: **36 tree FBX models, 8 bush FBX models, and 44 matching PNG textures**. Source files are unchanged. Archive/file SHA-256 hashes and attribution are recorded in `provenance.json`.

`gameplay/environment/tree_pack.tscn` is attached by one hook in `match_world.gd`. It places 24 trees and 12 bushes outside the 24 m arena, plus a cosmetic ground plane beneath the surroundings. The layout is deterministic, so each peer sees the same scenery without network replication. No tree, bush or backdrop collision is added: these are scenery rather than combat cover.

Materials explicitly use the matching PNG, alpha scissor, two-sided rendering and nearest filtering with mipmaps. FBX source heights vary; the wrapper normalizes them by uniform visual scale and places their bases at Y=0. The game's lighting remains unchanged.

## Use

1. Pull the repository and run `git lfs pull` for FBX/PNG objects.
2. Open `project.godot` in Godot 4.7.2 Standard and wait for import. Press F5 and Host/Join; trees appear beyond the arena walls.
3. To add the same scenery to another arena, instantiate `gameplay/environment/tree_pack.tscn`.
4. To change the layout, edit the two placement loops in `tree_pack.gd`.
5. To add one plant programmatically, call `add_plant("tree01", Vector3(20, 0, 10), 6.0)` on a TreePack instance in the scene tree. The last argument is desired height in meters. IDs run from `tree01` to `tree36` and `bush01` to `bush08`.

The raw FBX files can be inspected directly in the editor, but use the wrapper to get the supplied texture/cutout settings and normalized height. These are low-poly PSX models with image-based foliage; they do not include wind animation or full-volume photorealistic leaves.

## License/source

The ZIP has no license file. We verified the [publisher's page](https://elegantcrow.itch.io/psx-retro-style-tree-pack) on 2026-10-16: Elegant Crow identifies the models as CC0 and separately explains the CC0Textures/Pixabay origins of the imagery. See `content/environments/tree_pack/LICENSE-SOURCE.md` for the source record and links. This project does not relabel all source imagery as CC0.

## Verification

```sh
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --script tests/tree_pack_test.gd
python3 scripts/smoke_test.py "$GODOT"
```

The focused test loads all 44 model/texture pairs, checks foliage materials, normalized height, grounded bases, uniform scale, deterministic placement and absence of physics collision. Editor import and the existing multiplayer suite passed; a visible Metal/Mobile run confirmed foliage cutouts and trees surrounding the arena. This does not establish performance or two-Mac play acceptance.
