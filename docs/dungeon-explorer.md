# Dungeon explorers

`scripts/dungeon_explorer.py` runs the real Red Descent map in Godot, using three instances of the production player scene for collision exploration. Separate controls run the production `RaiderMob`, `HostileMob.walk()` and `MobNavigation`; they do not give enemies the inspector's map knowledge. Gameplay and level code are unchanged.

```sh
python3 scripts/dungeon_explorer.py "$GODOT" --mode fast --output /tmp/explorer-fast
python3 scripts/dungeon_explorer.py "$GODOT" --mode full --output /tmp/explorer-full --capture
# Capture synchronized inspection passes from a completed run, without repeating its exploration:
python3 scripts/dungeon_explorer.py "$GODOT" --output /tmp/explorer-full --capture-only
# All three recorded crawler poses, with six viewing directions each:
python3 scripts/dungeon_explorer.py "$GODOT" --output /tmp/explorer-full --capture-only --capture-workers 3
# Repeat the exact seed/mode/budget and compare the actual enemy outcomes:
python3 scripts/dungeon_explorer.py "$GODOT" --replay-from /tmp/explorer-full --output /tmp/explorer-replay
# Compare a run after changing gameplay code; keep the harness and scenario settings identical:
python3 scripts/dungeon_explorer.py "$GODOT" --mode full --compare /tmp/explorer-full --output /tmp/explorer-after
```

Windowed commands go through `scripts/godot_bg.sh`; they stay unfocused and silent. `--lenses forward,down` restricts the camera directions during a quick iteration. Horizontal lenses follow the crawler's recorded travel direction (or its goal when stationary); up/down are vertical. The camera sits 0.65 m above the recorded capsule centre. A capture records its source physics tick and heading. Cameras use recorded crawler poses rather than claiming an autonomous camera inspected every surface. Actors are hidden consistently in all static-architecture inspection passes.

## Outputs

- `telemetry.json`: run identity, sampled multi-level floor cells, headroom, normals, collider paths, coverage, recovery restarts, bounded motion traces, enemy decisions, detector controls, geometry inventory and capabilities.
- `issues.json` / `REPORT.md`: severity-sorted findings, observations versus candidates, and coverage limits.
- `level-*.png`: top-down maps in 2 m height bins. Green is physically visited, amber sampled but unvisited, grey clearance blocked and red an issue location. These bins are not architectural floor IDs; telemetry retains each height separately.
- `captures.json`, `objects.json`, `crawler*-*.png`: synchronized camera passes and their legends. Ordinary screenshots are separate from diagnostic overrides.
- `identity.json` / `capture-identity.json`: committed revision, hashes of the harness and relevant game/layout source, and tracked dirty paths. Capture refuses gameplay/layout source drift. These are not a complete hash of uncommitted binary asset bytes.
- `travel-times.json`: every adjacent area pair in both directions, with Dijkstra estimates assembled from successful observed directed capsule steps between visited area representatives. They are simulated times assembled from multiple steps, not a single timed trip. Missing connections are unchecked. `comparison.json` marks changes as paired only when seed, mode, budget and harness match.

| Pass | Meaning |
| --- | --- |
| color | Game materials and scene lighting, with UI hidden |
| objects | Stable color per render object; `objects.json` maps colors to paths, assets, triangle counts, LOD ranges and instance counts. One MultiMesh object can contain many instances. |
| depth | Camera-space depth / 30 m as greyscale, displayed through the output color encoding; black background is unknown, not zero-distance geometry. This is a visual aid, not a numeric depth export. |
| normals | World-space mesh normal XYZ mapped to RGB; not the normal-map texture |
| intersections | Green markers at sampled triangle-edge crossings between different render objects, shown through occluders. Mortar/stone contacts can be intentional. |
| collision | Green wire outlines of actual collision shapes, shown through occluders |
| clearance | Nearby sampled cells: green passes capsule/headroom queries, red is blocked. This does not certify reachability. |

Thickness is deliberately omitted: the level includes open mortar/plaster sheets, so a generic thickness image would be ambiguous. Diagnostic material overrides preserve flagstone outline clipping, but not arbitrary shader peeling, displacement or transparency. Always compare the color view.

## Behavior and interpretation

The 0.5 m survey retains multiple matching heights at the same X/Z, using room polygons and route widths as privileged inspection bounds. It samples collision layers down to -55 m, keeps headroom and capsule clearance, and builds a four-neighbour graph. A reversed collision triangle is retained with its reported normal: actual walking establishes traversal. Decorative undersides with insufficient headroom remain blocked.

Explorers physically visit frontiers. Independent starts prioritize the root tunnel, nave, return stair, choir and stair halls, then rotate through all sampled areas and their edges every 600 ticks. This prevents the entrance from consuming the whole budget. Teleports occur only at logged restarts (independent area trial, exhausted component, fall or snag recovery). A locally visited cell after a restart does not establish connectivity from the entrance. Components describe the sampled graph, which can contain edges that actual walking later rejects. Unvisited cells are untested, not proven unreachable. The trial budget is explicit (`--ticks`, fast default 3,600; full default 36,000 ticks per crawler, fixed 1/60 s steps).

The enemy controls include clear floor, stacked floors, obstacles added after navigation was built, another enemy physically blocking the path, removal of that actor, static detours, unreachable goals, cover, target memory expiry, reacquisition and returning home. Two guards also perform locomotion trials on their actual dungeon hall grids. Locomotion controls call production `walk()` and `move_and_slide()`; the perception/action scenario runs the production physics callback. The trace records goals, path waypoints, state, perceived target, last seen position, memory, velocity, ground state and collision paths. Controls verify the detector with both valid arrivals and false successes, plus a real capsule falling off a test floor; a fixed enemy may stop reproducing a bug without invalidating the detector.

Floor/ceiling inspection is a separate sampled render-mesh audit, checked against a known visual gap over solid collision, a valid floor, an instanced floor and a reversed sheet. MultiMesh instance transforms are included in surface probes. It recovers actual triangle winding because the engine's intersection normal faces the incoming ray. Blocked camera positions are skipped and counted. Fast room probes are 3 m apart; full probes are 1 m apart. Three lanes per route are sampled at 2 m in fast mode and 0.5 m in full mode, including corridor ceilings outside room volumes (also when a route is raised above the room's base floor). Neither certifies centimetre-wide seams. Positive render-height differences can be legitimate rubble/props; they are separate candidates. Intersection samples are bounded and do not find self-intersections inside merged meshes or intersections between MultiMesh instances. Geometry totals include stored explicit LOD objects; they are not simultaneous rendered triangles, GPU cost, or a thermal benchmark. Arbitrary interaction semantics and complete dynamic navigation remain unchecked. Crowd obstruction is measured, not automatically fixed.

The runner fails on Godot script/errors even if the engine exits zero or prints a completion marker. Reports may contain actual game defects while the harness itself passes. Existing root-material `specular` remapping and Metal shutdown texture-RID warnings are retained in logs; they are not silently removed. Manual input, camera feel, Tailscale and sustained performance remain separate acceptance.
