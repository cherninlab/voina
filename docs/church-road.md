# Church road torches

The north trail from the village gate to the church graveyard is marked by small burning stakes (`gameplay/environment/church_road.gd`, node `ChurchRoad`, built by `MatchWorld.build_arena` after the village). The road follows `ChurchSite.road_x`, the same curve that clears the trail through the trees, from `ROAD_START_Z` (-30) to `ROAD_END_Z` (-90). Cosmetic only: no collision, navigation obstacles, gameplay or network state.

## What is there

- Seven deterministic stakes (seed 86086) alternate sides 2.3–2.7 m from the centre line, every 7–9 m, from z -31 to z -81.5. The line stops short of the church gate at z -87.5, whose stone pillars carry their own torches (T-085).
- Five are lit. The third from the end is cold and knocked over to about 21°; the last before the gate has guttered out and only smoulders (red ember glow, a thin smoke wisp, an occasional spark).
- A stake is a slightly crooked, bowed, tapering pole (1.2–1.4 m above ground, sharpened into the mud, soot creeping down from the head) with a lumpy pitch-rag head. Ember cracks glow in the head; its rim is a bed of coal.
- The flame is a camera-facing upright quad. Scrolling noise tears a teardrop body into licking tongues, coloured from deep red at the edges through saturated orange to a yellow core. It uses premultiplied blending so it stays orange against a bright sky. A soft additive halo stands in for bloom and lit haze, and CPU embers and a faint lit smoke wisp rise from it.
- Each lit torch has a warm non-shadowing `OmniLight3D` (range 7 m, attenuation 1.6, so each torch makes its own pool). Energy flickers from smooth time noise, stable between frames. The light never moves: moving a light re-pairs every mesh it touches.
- Additive glows skip engine fog, which would brighten them. They fade by the live environment's exponential fog density instead, read every half second, so they sink into the forest fog with distance.
- A wet trodden mud overlay covers the trail, 3.8 m wide, with ruts, damp stretches and a few dark puddles that catch the torch glints. Its shoulders are noise-broken and fade to nothing, and it fades in and out at both ends.

## Light budget and the Mobile per-mesh limit

Five omni lights, out of a budget of ten. Godot 4.7.2 Mobile/Metal applies at most eight omni lights to one mesh instance. This was measured: one plane under fourteen lights showed eight pools. The scene culler keeps the eight with the lowest `distance from the mesh's AABB centre / (range * energy)`, as a shifted-plane test also showed. Those slots are fixed when pairing changes, and a slot held by an off-screen light is skipped, not refilled.

The landscape is one 576 m mesh centred under the village, so every lantern, church or forest light in the level competes for its eight slots. Today the torches win them because of their range and energy. A capture with eight tiny decoy lights at the landscape's centre (`road-night-crowded-no-overlay-midroad.png`) shows the bare trail losing every pool.

The pools therefore land on the overlay. It is split into eight 8 m chunks, and each chunk is its own mesh that pairs with at most three torch lights. The chunk vertices sample the exact landscape triangles (`WoodlandVillage.landscape_surface_height`) and, between z -27 and -37, the village's blended apron. They are lifted 3 cm.

## Captures and checks

```sh
"$GODOT" --path . --script scripts/capture_church_road.gd -- --host --port=7796 --shading-ephemeral --capture-dir=/absolute/output/folder
```

Run it without `--headless`. It fails unless all of these hold:

- the road built;
- nothing under it collides;
- there are at most ten lights;
- every chunk overlaps at most eight omni lights;
- 12,000 overlay vertex, edge-midpoint and centroid samples sit 0–8 cm above the collision ground (measured 2.0–4.0 cm);
- every stake foot is on the ground.

It then saves real Metal frames through the game's wide-angle lens:

- the north gate, mid-road at eye height, a torch close-up and a high overview in today's grade (`road-day-*`);
- the gate and mid-road at dusk;
- all views plus a closer high view and a view back to the village at night.

The dusk and night grades dim the sun and sky, detach the baked daylight bounce and thicken a cold blue-grey fog inside the script only. `road-night-no-overlay-*` and `road-night-crowded-*` are the overlay evidence above. `--shading-ephemeral` keeps the machine's saved shading theme out of the run.

## Not done

- The real night and forest-fog grade belongs to the haunted forest pass (T-083 storm, theo-claude-12 fog). The torches were judged under today's storm daylight and the capture-only dusk and night grades, not under that final grade.
- Torch light is constant, so pools also show in daylight.
- The glow fade models exponential fog only, not height fog.
- Flames are upright quads and look thin from directly overhead.
- No shadows and no crackle sound.
- The trail grass, fern and tree batches are single instances spanning the whole trail and compete for eight lights by the same rule. More lights near them could cost them their torch light.
- If the village's landscape or apron formulas change, the overlay must follow; the capture's clearance check catches a mismatch.
- No M2 frame-cost or thermal measurement.
