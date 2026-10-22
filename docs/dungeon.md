# Maps: Village, Cinder Crypt, White Room

Host game → **Map** picks the map before Start game: Village (the default), Cinder Crypt or White Room. The village's encounter and round switches only appear for the village. Joiners need nothing: the host's authentication answer names its map and the joiner builds it before anyone spawns (`MAP_ADOPTED: <id>` in its log). The list lives in `gameplay/maps.gd`.

Without the menu, `--map=village|crypt|white_room` (or `--dungeon`, the same as `--map=crypt`) chooses the map for an automatic `--host` or `--server`:

```sh
python3 scripts/playtest.py host --map crypt
python3 scripts/playtest.py host --map white_room
python3 scripts/playtest.py join HOST_ADDRESS
```

`playtest.py host` uses the clean copy of the tip of main. Direct development launch:

```sh
GODOT=/path/to/Godot scripts/godot_bg.sh --path . -- --host --map=white_room
"$GODOT" --headless --path . -- --server --map=crypt
```

## White Room

A plain, evenly lit, blank 20 × 28 m room for combat testing, shown in the **Overexposed** shading theme. Your own theme comes back on the other maps; picking one with T or the tweaks panel inside the room makes it yours. Each map's theme is `GameMaps.SHADING`. Players start at the south end. Classic (unhooded) raiders arrive from four gates at the far corners and sides: three at once, then one every 4 s while fewer than six are present, for as long as the session lasts. They hold the middle of the room, from where the whole room is in sight. The corner label counts raiders present and felled. No ambience plays. Esc → Leave game ends it.

## Cinder Crypt

Start in a sheltered entrance. Pass either side of the inscription screen into the burial hall. Its central sarcophagus and columns make two reconnecting routes for fighting and retreating. Continue through the north arch to the blue altar chamber. Defeat all five cultists and reach the altar to see **CLEARED**. The objective appears while the cursor is captured.

The cultists reuse the existing host-owned raider AI, 60 health, melee jab, block/parry and weapon damage. They do not respawn. Death returns the player to the entrance; defeated enemies stay dead for that session. Esc → Leave game → Host game starts a fresh encounter. Village PvE and round-match switches do not change this dungeon encounter.

This is a compact single-floor layout and combat playtest. There is no loot, boss, locked-door progression, saving, generation or transition between maps. Four spawn positions are separated in the entrance. Manual input/camera feel and two-Mac Tailscale acceptance are still required.

Geometry is original procedural stonework. Stone textures reuse the repository's licensed KitBash3D Valhalla materials, as already used by `church_grounds.gd`; provenance is in `content/environments/valhalla/`. Flames reuse the original church-road shader. Cultist/character provenance remains in `content/mobs/hooded_cultist/` and `content/characters/quaternius/`. Wind/fire audio reuse the catalogued clips in `content/audio/`. No new external assets are introduced.

Verification:

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
python3 scripts/dungeon_smoke_test.py "$GODOT"
GODOT="$GODOT" scripts/godot_bg.sh --path . --script scripts/capture_dungeon.gd -- --host --dungeon --shading-ephemeral --shading=Natural --capture-dir=/tmp/cinder-crypt
```
