# Dungeon explorers

`scripts/dungeon_explorer.py` runs the real Red Descent map in Godot, using three instances of the production player scene for collision exploration. Separate controls run the production `RaiderMob`, `HostileMob.walk()` and `MobNavigation`; they do not give enemies the inspector's map knowledge. Gameplay and level code are unchanged.

```sh
python3 scripts/dungeon_explorer.py "$GODOT" --mode fast --output /tmp/explorer-fast
python3 scripts/dungeon_explorer.py "$GODOT" --mode full --output /tmp/explorer-full --capture
# Capture synchronized inspection passes from a completed run, without repeating its exploration:
python3 scripts/dungeon_explorer.py "$GODOT" --output /tmp/explorer-full --capture-only
# All three recorded crawler poses, with six viewing directions each:
python3 scripts/dungeon_explorer.py "$GODOT" --output /tmp/explorer-full --capture-only --capture-workers 3
```

Windowed commands go through `scripts/godot_bg.sh`; they stay unfocused and silent. `--lenses forward,down` restricts the camera directions during a quick iteration. The lens names are world-aligned, with a camera 0.65 m above the recorded capsule centre. A capture records the source physics tick. Cameras use recorded crawler poses rather than claiming an autonomous camera inspected every surface.

## Outputs

- `telemetry.json`: run identity, sampled multi-level floor cells, headroom, normals, collider paths, coverage, recovery restarts, bounded motion traces, enemy decisions, detector controls, geometry inventory and capabilities.
- `issues.json` / `REPORT.md`: severity-sorted findings, observations versus candidates, and coverage limits.
- `level-*.png`: top-down maps in 2 m height bins. Green is physically visited, amber sampled but unvisited, grey clearance blocked and red an issue location. These bins are not architectural floor IDs; telemetry retains each height separately.
- `captures.json`, `objects.json`, `crawler*-*.png`: synchronized camera passes and their legends. Ordinary screenshots are separate from diagnostic overrides.

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

Explorers physically visit frontiers. Teleports occur only at logged restarts (initial spawn, exhausted component, fall or snag recovery). A locally visited cell after a restart does not establish connectivity from the entrance. Components describe the sampled graph, which can contain edges that actual walking later rejects. Unvisited cells are untested, not proven unreachable. The trial budget is explicit (`--ticks`, fast default 3,600; full default 36,000 ticks per crawler, fixed 1/60 s steps).

The enemy controls include clear floor, stacked floors, obstacles added after navigation was built, static detours, unreachable goals, cover, target memory expiry, reacquisition and returning home. Locomotion controls call production `walk()` and `move_and_slide()`; the perception/action scenario runs the production physics callback. The trace records goals, path waypoints, state, perceived target, last seen position, memory, velocity, ground state and collision paths. Controls verify the detector with both valid arrivals and false successes; a fixed enemy may stop reproducing a bug without invalidating the detector.

Floor/ceiling inspection is a separate sampled render-mesh audit, checked against a known visual gap over solid collision and a valid floor. Fast room probes are 3 m apart; full probes are 1 m apart. Neither certifies centimetre-wide seams. Intersection samples are bounded and do not find self-intersections inside merged meshes. Geometry totals include stored explicit LOD objects; they are not simultaneous rendered triangles, GPU cost, or a thermal benchmark. Crowd avoidance, arbitrary interaction semantics and complete dynamic navigation remain unchecked.

The runner fails on Godot script/errors even if the engine exits zero or prints a completion marker. Reports may contain actual game defects while the harness itself passes. Existing root-material `specular` remapping and Metal shutdown texture-RID warnings are retained in logs; they are not silently removed. Manual input, camera feel, Tailscale and sustained performance remain separate acceptance.
