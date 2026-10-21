# Cinder Crypt — first dungeon playtest

The village remains the default map. Only `--dungeon` selects this second map; there is no map menu or village portal yet. Both host and joiners must use the flag. Map disagreement is refused during authentication, before players spawn, including when build checks are bypassed.

From any checkout, with Godot 4.7.2 configured:

```sh
python3 scripts/playtest.py host --dungeon
python3 scripts/playtest.py join HOST_ADDRESS --dungeon
```

These use the clean, pinned playtest copy. Direct development launch:

```sh
GODOT=/path/to/Godot scripts/godot_bg.sh --path . -- --host --dungeon
# Dedicated host; joiners still need --dungeon:
"$GODOT" --headless --path . -- --server --dungeon
```

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
