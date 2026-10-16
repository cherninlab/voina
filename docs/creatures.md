# Ambient birds

Four passive birds now perch on the four greybox cover blocks in a hosted arena. They occasionally take a short flight, flee when a player comes within 3.5 metres, and return once their home is clear within five metres. They work alongside the sandbox, optional PvE raiders, and optional match mode. Join normally; the host runs the flock automatically. No extra control or mode switch is needed.

These are small environmental birds, separate from hostile mobs. They have **no collision, health, hit target or combat interface**. They cannot damage players or obstruct a sword, beam or bolt. This keeps ambient life separate from combat and the ongoing player sword work.

## Implementation and assets

- `gameplay/wildlife/bird_flock.gd`: host simulation for perch timers, flight routes, flee distance and return behavior. Flights rise to four metres before travelling horizontally, above the current static arena cover. Birds stay inside a 19 × 19 metre ground-plane area.
- `gameplay/wildlife/bird_visual.gd`: original low-poly birds built from Godot meshes, with procedural wing beats, folded wings, bobbing and flight-facing. There are no downloaded textures, models, rigs or clips, and no third-party asset license or Git LFS additions.
- `gameplay/wildlife/wildlife.gd`: the `Wildlife` autoload. The existing `match_world` lifecycle group starts and clears the flock. Peer 1 owns its state and positions; one synchronizer sends four positions, four behavior states and the active flag at 20 Hz. Clients interpolate visuals and animate wings locally. Fixed bird identities allow late joiners to receive current state without a new dynamic spawner.

The homes are intentionally tied to the current four cover blocks. Change `BirdFlock.HOMES` when moving those blocks. Routes assume the current flat arena with obstacles below the flight height; they do not navigate arbitrary buildings, moving obstacles or tree canopies. The birds are stylized placeholders, with no sound, attacks, breeding, loot or ecosystem simulation.

## Verification

```sh
"$GODOT" --headless --editor --path . --quit
python3 gameplay/wildlife/tests/smoke_test.py "$GODOT"
python3 scripts/mob_smoke_test.py "$GODOT"
python3 scripts/smoke_test.py "$GODOT"
```

The focused check covers idle and wandering, takeoff clearance, fleeing, waiting while a perch is occupied, returning, and an escape along the arena boundary. A real ENet pair starts the host first, lets a bird flee, then joins a client to verify current position/state, host simulation authority and cleanup. CI runs this alongside existing combat and PvE checks. Human visual acceptance and two-Mac Tailscale play remain separate checks.
