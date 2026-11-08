# Builder design rules

How SECHA's procedural builders decide what to build. Theo (2026-11-08): the builders are too stupid, and too much of the dungeon looks ugly or primitive. This document is the shared rulebook for the builder tasks. H-022 doors, H-023 bridges, H-024 tunnels and H-025 the dungeon generator follow it.

It extends the room and passage rules in [dungeon-architecture.md](dungeon-architecture.md), which already work well (openings only where a route crosses a wall, one generator per element, a doorway sized by its crossing), and the bake loop in [procedural-generators.md](procedural-generators.md). It does not repeat them.

## The problem in one sentence

Each builder makes its piece alone from a centreline and a width. It never asks what holds the piece up, what the piece meets, how old it is, or what the player sees from where they stand. The result is correct but generic: a bridge is a straight plank sheet, a tunnel has one cross-section, a room is an empty box with props in a row.

## Ranked gaps (actual game, 2026-11-08)

Frames are in [content/art_direction/builder_gaps_v1/](../content/art_direction/builder_gaps_v1/README.md). They are ranked by how much of the player's view they spoil.

| # | Gap | Frames | Owner |
| --- | --- | --- | --- |
| 1 | **Bridges carry nothing and nothing carries them.** A straight deck of identical boards and posts floats beside towers with no bearers, brackets, struts or bearings. Ageing moved boards 1.8 cm at most, leaned no post, and kept the deck within 7 mm of flat (`procedural_bridge_v1/high_span.json`). Missing boards show pale plates. | 01–04 | H-023 |
| 2 | **The shaft is still old boxes.** Towers and outline walls are flat slabs with a tiling texture and small decals. These are the largest surfaces on screen from every crossing. | 01, 05, 06 | Open work in dungeon-architecture.md. Needs a new task. |
| 3 | **The upper crossing is slabs on thin black beams** with a plain cylinder column. | 06 | H-023 for the timber, a new task for the masonry |
| 4 | **Tunnels and junctions are uniform and clean.** One stone size and tone, no wear, damp, growth or rubble at the base. Junction arches read as thin flat slabs. | 07, 08 | H-024 |
| 5 | **No doors exist,** so every opening is the same empty arch. | 07, 08 | H-022 |
| 6 | **Rooms have no composition.** The nave is a dark empty floor. The ossuary shows no bones and lines identical crates along the wall. | 10, 11 | Dressing, H-025 |
| 7 | **One prop is repeated everywhere:** the post-and-box torch. | 04, 05, 07 | Dressing |
| 8 | **Stair halls use box parapets** and plain walls. | 09 | H-024 or a stair task |

## What good procedural building does

These are techniques, not looks. Never copy another game's art. Sources are linked so the claims can be checked.

- **The situation creates the element.** In Tiny Glade, a path crossing a wall's footprint is what makes the opening. Its width and host choose a door or an arch, and a path through a building becomes a tunnel. An arch too wide to stand gets pillars automatically. ([80.lv interview](https://80.lv/articles/exclusive-tiny-glade-developers-discuss-bevy-proceduralism-publishers-cozy-games), [pillars](https://80.lv/articles/anastastia-opara-s-procedural-wall-generator-now-has-pillars))
- **Neighbours decide what a piece becomes.** In Brushland, a house enclosed by roads becomes a church, and one among fields becomes a windmill. There are no prefabs. ([Steam](https://store.steampowered.com/app/5163450/Brushland/); design intent only, no technical talk yet.)
- **Pieces are chosen by their corner configuration, and decoration comes in a second pass.** Townscaper solves the hard constraints first. Then props go where there is free space, and windows are cut as stencils so none is split across a corner. Bad North bans identical or mirrored tiles side by side, validates walkability, and retries a failed island. ([How Townscaper works](https://www.gamedeveloper.com/game-platforms/how-townscaper-works-a-story-four-games-in-the-making))
- **Generation runs coarse to fine.** Caves of Qud sets the architecture first, then fills detail per region with its own style, then ensures connectivity and places creatures and items. ([GDC 2019](https://gdcvault.com/play/1026263/Math-for-Game-Developers-Tile), [WFC tips](https://www.boristhebrave.com/2020/02/08/wave-function-collapse-tips-and-tricks/))
- **The layout is a loop, not a tree.** Unexplored builds dungeons from cycles (two routes with different obstacles, lock and key, shortcuts back), and only later decides whether an obstacle is a gate, a collapse or a guardian. ([Dungeon generation in Unexplored](https://www.boristhebrave.com/2021/04/10/dungeon-generation-in-unexplored/))
- **Art direction is part of the generator.** Opara's Pica Pica work composes a focal point first, keeps secondary pieces quiet, and leaves deliberate gaps. A compositional-balance solver is kept deliberately imperfect so the result doesn't look arranged. ([CEDEC 2018](https://media.contentapi.ea.com/content/dam/ea/seed/presentations/cedec-2018-functional-symbiosis-of-art-direction-and-proceduralism.pdf))
- **Wear is a field around features.** Tiny Glade stores each vertex's distance to the nearest window, and the shader damages plaster near openings. ([80.lv](https://80.lv/articles/procedural-windows-in-pounce-light-s-tiny-glade-get-an-upgrade/))

## Core rules for every builder

1. **Situation in, form out.** A builder first writes a *situation* for each element it will make:
   - its anchors and what they are made of (rock, masonry, timber);
   - span, drop below, and headroom;
   - its neighbours;
   - its load (route, bell, crowd);
   - its age and exposure (damp, drips, fire);
   - its *importance*: main route, side route, or vista seen from afar.

   It then picks a form from a catalogue by rules, and records the situation, the rule that fired and the form in its JSON report. No builder makes the same form everywhere.
2. **Coarse to fine, and each pass reads the earlier ones.** The pass order is:
   1. layout graph
   2. masses (rooms, shaft, towers)
   3. connectors (passages, bridges, stairs)
   4. openings and doors cut into their hosts
   5. supports
   6. ageing
   7. dressing
   8. lights

   A later pass changes an earlier output only through declared cut and attach points (a doorway, a bearing seat, a corbel slot), never by overlapping it.
3. **Every load reaches rock.** Each element names the path its weight takes to rock or to a bigger element: deck → bearer → corbel → wall, or vault → pier → footing. The report lists that path, and a validator fails any element that starts in mid-air or rests on a thinner piece than itself.
4. **Span limits create structure.** When a span passes its material's limit, the builder adds a pier from below, knee braces, a strut to the nearest wall, or a rib. It never just stretches the piece. Limits live in one table per material so all builders agree.
5. **Imperfection has a cause and a visible budget.** It comes in three layers:
   - a designed irregularity before physics: camber or sag, uneven post heights, irregular board widths, wandering courses;
   - a physics settle;
   - wear fields measured from causes: distance to openings, floor contact, drips, junctions, walking lanes, light.

   Every element states its budget at play distance (about 4–8 m), and its review must show the imperfection there. Starting budgets for H-023 to tune with Theo: a timber deck sags 4–8 cm at mid-span per 6 m, posts lean 1–4°, boards yaw up to ±2° with joint gaps of 0.5–2 cm, and one in 20–40 boards is missing or replaced. Hard limits: the walking lanes stay inside the existing deck test, no step over 1.5 cm on a lane, and no hole a foot can enter on the main route.
6. **No twins.** Two neighbouring pieces are never identical or mirror-identical. A repeated prop varies in at least two of: variant, scale, rotation, wear and attached dressing. The validator hashes each piece against its neighbours.
7. **Validate, then retry.** A failed check (connectivity, walkability, capsule clearance, interpenetration over 1 cm, the load path, the no-twins rule) rejects the seed. The builder retries with another seed or changes the situation, as dungeon-architecture.md rule 4 already does for doors. It never patches the result by hand, and never silently exports a failure.
8. **Compose, don't line up.** Each room and each vista has one focal element. Dressing forms clusters with a counterweight and deliberate empty space. Props never stand in rows along a wall unless the room is a store whose purpose is rows.
9. **Same-camera proof.** Every change ships matched before/after frames from the existing capture sets, plus a play-distance frame of the imperfection budget. Use real renders, never only numbers. See the [art quality bar](#art-direction-checklist).

## Element rules

### Bridges (H-023)

The bridge type comes from its situation. The layout's `wood` flag stays a hint that the rules may override, and the report says so.

| Situation | Form |
| --- | --- |
| span ≤ 3 m | plank deck on two bearers seated in wall pockets |
| 3–8 m, a floor or ledge within ~10 m below | braced trestle: legs with cross and knee bracing, footings set on that floor |
| 3–8 m, deep drop, masonry at both ends | deck on bearers carried by stone corbels, with knee braces from iron brackets into the wall (paintover 4) |
| over 8 m, deep drop | suspension: chain or rope catenary from anchor plates, hangers, a deck that follows the sag |
| masonry at both ends, stone route | stone arch with voussoirs, using the same masonry toolkit as passages |
| over the limit of any form | add a pier from the floor below, or a strut to the nearest tower |

- **Ends:** a bridge always lands on an abutment, a seat cut into rock or a bearing course in masonry. Never butt-join a deck to a wall face.
- **Bends and landings:** a node in the route is a landing platform with its own posts, not a mitred kink in a plank sheet.
- **Rails** follow the deck's real sag, and the rope or chain hangs by its own catenary.
- **Furniture:** chunky parts (corbels, knee brackets, finials, anchor plates, post feet) may come from CL3D. Thin parts stay procedural.
- **Physics** ages the designed shape inside the budget in core rule 5. A missing board shows the drop or the bearer below, never a plate.

### Tunnels and passages (H-024)

- **Form by context:**
  - rough-hewn rock where the route is cut into the shaft's rock;
  - masonry vault where it is built;
  - timber-shored mine where it is a later dig.

  A passage records why it has its form.
- **Profile changes along the length:** the passage narrows at a gate, lowers under a room, steps down on a slope, and widens where routes meet.
- **Junctions** are pieces chosen by how many passages meet and at what angle: a mitre, a groin-vaulted bay, or a small chamber. Arches through a wall are full-depth rings, never thin slabs.
- **Wear fields:** damp and growth rise from the floor and drips, soot gathers above lights, and edges are worn along the walking lane. Rubble and fallen stones gather at the base.
- **Partial collapses** are allowed off the lane, and always keep the route clear.

### Doors and openings (H-022)

- **Openings come from crossings,** as in dungeon-architecture.md rules 1–4. The door is built in the opening's own frame, so door and doorway are one element.
- **Form by situation:**
  - a narrow opening in a domestic or cell wall gets a plank door;
  - a wide one, a gate or arcade;
  - a defended threshold, a grate or portcullis;
  - an abandoned route, a bricked-up or boarded opening;
  - a fought-over route, a broken door with its leaf fallen.
- **State:** open, ajar or closed. Doors on playable routes stay passable unless gameplay asks otherwise.
- **Ageing:** a leaf sags on a failed hinge, iron rusts in streaks below its straps, and the threshold is worn in the lane.

### Stairs

- A stair is carried by masonry or by stringers on a support. A parapet is built stone or rail, never a box.
- Treads wear in the walking line and are less worn at the edges.

### Shaft, towers and supports

- Treat the shaft wall, towers and the central wall as masonry hosts built by the same toolkit, instanced as dungeon-architecture.md already plans, so bridges and corbels have real stone to bear on.
- Where a support is missing for a span, the builder adds one (core rule 4). It doesn't hide the gap in darkness.

### Dressing and light

- Each room's purpose decides its dressing: an ossuary has bones in niches, cells have chains and straw, a chapel has an altar and benches.
- One focal element per room. Clusters, not rows.
- Light sources vary: wall sconce, standing torch, candle cluster, brazier. Each source's type follows its host: a sconce on a wall, a brazier on a floor, candles on a ledge. A light always lights something worth seeing.

## Dungeon layout (H-025)

- Generate a graph first: one main loop from the entry to the goal, with secondary loops, lock-and-key pairs, shortcuts back to earlier spaces, and one-way drops.
- Resolve abstract obstacles (gate, gap, collapse, guardian) only after the region's style and shape are known. A gap becomes a bridge whose form comes from the bridge rules.
- Give regions their own style (chapel quarter, cells, mine) with their own catalogues, as Caves of Qud runs per-region generation.
- Pace the route: vistas across the shaft, choke points, fights, and quiet rests with a light.
- Validate connectivity and walkability, and keep each seed's report. Nothing replaces Red Descent until Theo approves a seed.

## Art-direction checklist

Before showing any builder output, check it in real Mobile/Metal frames at play distance against Theo's paintovers (`content/art_direction/theo_paintovers_v1`, especially 4) and his crypt references:

- Rough squared stone with tight dark joints, arches on piers, barrel and groin vaults.
- Wet dark stone, red roots or veins, rubble along the base, rope-lashed timber.
- Warm candle and torch light against cold or red fill. Fog gives depth.
- Big plaster loss in patches, not small decals, plus moss and hanging growth where water runs.
- Every element has a visible reason and a visible load path. Nothing clips, floats or repeats as a twin.
- The imperfection is visible at play distance, and it stays walkable and never extreme.
- Say plainly when a pass is still too subtle. Never present invisible changes as progress.

## Status

- Written for H-021, 2026-11-08. Builders adopt the rules as they are rebuilt. Existing output isn't retroactively out of contract until its owning task rebuilds it.
- Theo's review of this document is recorded on H-021.
