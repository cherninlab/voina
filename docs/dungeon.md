# Maps: Village, Cinder Crypt, White Room, Long Grass

Host game → **Map** picks the map before Start game: Village (the default), Cinder Crypt, White Room or Long Grass ([long-grass.md](long-grass.md)). The village's encounter and round switches only appear for the village. Joiners need nothing: the host's authentication answer names its map and the joiner builds it before anyone spawns (`MAP_ADOPTED: <id>` in its log). The list lives in `gameplay/maps.gd`.

Without the menu, `--map=village|crypt|white_room|long_grass` (or `--dungeon`, the same as `--map=crypt`) chooses the map for an automatic `--host` or `--server`:

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

## Cinder Crypt / Red Descent

`--dungeon` and the Cinder Crypt menu entry now load the first Red Descent level. The village remains the default. This replaces the old single-floor crypt.

The fixed layout has an irregular, roughly 50 m wide shaft, a 62 m tall architectural shell, an uneven central masonry spine, and two skewed timber crossings at different heights. The main route descends 28 m through an upper guard hall, chapel approach, sloping central ledge, tall nave, lower tunnel and deep choir. The eastern switchback stair reconnects to the upper route. Optional cells, ossuary, bell hall and cave bypass reconnect to that route. Bridges and ledges change direction and elevation; there is no rectangular stack of flat floors.

Five existing cultists guard the upper hall and deep choir. Their navigation grids sample those two floor elevations independently. Combat, health and spawning remain host owned; players own movement. Defeat the five cultists and reach the deep choir altar area to see **CLEARED**. Defeated enemies stay dead until Leave game → Host game. The return stair is open from the start in this first version.

Four entrance spawns are separated. The camera now sweeps its sideways shoulder offset as well as its backward spring arm, preventing the cast origin from entering a side wall. Dungeon fall recovery uses -56 m rather than the outdoor -10 m threshold, so descending through the level does not teleport the player back to the entrance.

This is a structural and atmosphere playtest. There is no loot, boss, locked-door progression, saving, procedural generation or transition between maps. Guards pursue within their two halls, rather than navigating the whole stacked level. Manual input/camera feel and two-Mac Tailscale acceptance remain human checks.

### Materials and render iteration

The original architecture uses batched chamfered blocks and continuous collision ribbons at sloping turns. Torch shadows are limited to the six nearest practical lights. Distant wall flames and red reflected fill establish the shaft's depth. Coffins, burial recesses, rafters, a restraint frame and a bell provide side-hall landmarks.

The render-led study, earlier actual engine frames and exact ImageGen prompts are in `content/environments/red_descent/review/` (excluded from runtime import/export by `.gdignore`). Five generated textures ship in `content/environments/red_descent/`: stone albedo, normal and roughness; timber albedo and normal. Normal and roughness maps were generated from their albedo reference and visually checked after integration. They are 1254 px square native outputs; exact mathematical registration and seamless edge matching are not asserted. Mipmaps are enabled. These are real-time materials, not baked lighting maps. Source paths, prompts and hashes are in that folder's `generation.json` and provenance file.

The existing KitBash3D Valhalla floor/roughness materials and original church stone shader remain in use; their license/provenance is in `content/environments/valhalla/`. Flames use the original church-road shader. Cultist/character provenance remains in `content/mobs/hooded_cultist/` and `content/characters/quaternius/`. Wind/fire audio reuse catalogued clips in `content/audio/`. New geometry is original; new bitmap materials were created with native OpenAI ImageGen from the project renders and selected concepts.

### Verification

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
python3 scripts/dungeon_smoke_test.py "$GODOT"
python3 scripts/dungeon_traversal_test.py "$GODOT"
"$GODOT" --headless --path . --script tests/camera_wall_test.gd
GODOT="$GODOT" scripts/godot_bg.sh --path . --script scripts/capture_dungeon.gd -- --host --dungeon --shading-ephemeral --shading=Natural --capture-dir=/tmp/red-descent
```

The traversal probe drives the actual player capsule with `move_and_slide`, gravity and floor snapping, at 4× simulation speed. It continuously walks the entrance-to-choir descent, the return stair and the exit; each optional loop starts at its own connection and is then walked continuously. It covers about 1050 m without jumping or teleporting between spans. The player controller is also enabled on the deep floor to test recovery behavior. This proves collision traversal, not human input feel. The ENet probe separately covers safe spawns, upper-hall pursuit/strikes, survivors/objective late join, client damage authority, clearing without replacement enemies, leave/rehost and host-map adoption.
