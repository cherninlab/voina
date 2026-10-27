# Dungeon explorer run

Build `aad22754bc0439d3f014e8a92af41cf54421ae23`; seed 186; mode full.

Actual capsule visits: 17190 / 21402 sampled walkable cells.
Budget: 36000 physics ticks per explorer; 3 explorers. Unvisited cells are untested, not proven unreachable.

Heatmaps: green = visited, amber = sampled walkable but unvisited, grey = clearance blocked, red = issue location. Levels are 2 m height bins, not room IDs.

## Capabilities

- capsule_exploration: implemented
- collision_survey: implemented
- crowd: actual enemy body obstruction and removal tested; production avoidance limitations reported
- enemy_scenarios: production enemy locomotion, blocked/changed paths, stacked floors, cover, memory, reacquisition, return home
- geometry_counts: per render object, explicit LOD range, material surfaces, MultiMesh instances; not GPU cost
- intersections: bounded geometric surface crossings between distinct objects; candidates only
- performance: unchecked
- visual_holes: sampled floor/ceiling mesh rays with known gap and solid controls; rendered captures are separate

## Area coverage

Independent starts and every recovery are logged; these visits do not establish entrance connectivity.

| Area | Visited | Sampled walkable |
| --- | ---: | ---: |
| room:antechamber | 523 | 548 |
| room:bell | 823 | 1348 |
| room:bones | 563 | 563 |
| room:cells | 448 | 472 |
| room:chapel | 1600 | 2050 |
| room:choir | 1055 | 2448 |
| room:entry | 704 | 712 |
| room:first_stair_hall | 459 | 593 |
| room:nave | 1425 | 2151 |
| room:ossuary | 1080 | 1222 |
| room:restraint | 1083 | 1141 |
| room:second_stair_hall | 393 | 402 |
| room:window | 368 | 368 |
| route:bell_loop | 281 | 322 |
| route:cave_bypass | 330 | 342 |
| route:central_ledge | 579 | 615 |
| route:chapel_approach | 130 | 132 |
| route:choir | 2 | 2 |
| route:entry | 89 | 89 |
| route:first_stair | 385 | 385 |
| route:high_span | 433 | 433 |
| route:low_span | 578 | 637 |
| route:nave | 369 | 369 |
| route:ossuary_loop | 464 | 544 |
| route:return_gallery | 525 | 643 |
| route:return_stair | 580 | 942 |
| route:root_tunnel | 1044 | 1052 |
| route:second_stair | 349 | 349 |
| route:upper_cells | 418 | 418 |
| route:upper_hall | 110 | 110 |

## Gameplay bot scenarios

| Scenario | Arrived | False arrival | Longest stuck (s) |
| --- | --- | --- | ---: |
| clear-floor | True | False | 0.0 |
| crowd-blocking | False | False | 2.0 |
| actor-obstruction-removed | True | False | 0.0 |
| stacked-floor | False | True | 0.0 |
| changed-obstacle | False | False | 2.0 |
| static-detour | True | False | 0.0 |
| unreachable-goal | False | True | 0.0 |
| cover-memory-reacquire-return | see trace | see trace | see trace |
| dungeon-hall-0 | True | False | 0.0 |
| dungeon-hall-2 | True | False | 0.0 |

Detector controls: 22/22 passed.

Travel estimates and unchecked directions are in travel-times.json. They sum observed edge times and are not single-trip timings.

<!-- capture-index -->
## Diagnostic cameras

Static architecture; actors hidden in every pass. See captures.json for source poses, ticks and legends; objects.json maps colors to actual render objects.

| View | color | objects | depth | normals | intersections | collision | clearance |
| --- | --- | --- | --- | --- | --- | --- | --- |
| crawler0-forward | [color](crawler0-forward-color.png) | [objects](crawler0-forward-objects.png) | [depth](crawler0-forward-depth.png) | [normals](crawler0-forward-normals.png) | [intersections](crawler0-forward-intersections.png) | [collision](crawler0-forward-collision.png) | [clearance](crawler0-forward-clearance.png) |
| crawler0-back | [color](crawler0-back-color.png) | [objects](crawler0-back-objects.png) | [depth](crawler0-back-depth.png) | [normals](crawler0-back-normals.png) | [intersections](crawler0-back-intersections.png) | [collision](crawler0-back-collision.png) | [clearance](crawler0-back-clearance.png) |
| crawler0-left | [color](crawler0-left-color.png) | [objects](crawler0-left-objects.png) | [depth](crawler0-left-depth.png) | [normals](crawler0-left-normals.png) | [intersections](crawler0-left-intersections.png) | [collision](crawler0-left-collision.png) | [clearance](crawler0-left-clearance.png) |
| crawler0-right | [color](crawler0-right-color.png) | [objects](crawler0-right-objects.png) | [depth](crawler0-right-depth.png) | [normals](crawler0-right-normals.png) | [intersections](crawler0-right-intersections.png) | [collision](crawler0-right-collision.png) | [clearance](crawler0-right-clearance.png) |
| crawler0-up | [color](crawler0-up-color.png) | [objects](crawler0-up-objects.png) | [depth](crawler0-up-depth.png) | [normals](crawler0-up-normals.png) | [intersections](crawler0-up-intersections.png) | [collision](crawler0-up-collision.png) | [clearance](crawler0-up-clearance.png) |
| crawler0-down | [color](crawler0-down-color.png) | [objects](crawler0-down-objects.png) | [depth](crawler0-down-depth.png) | [normals](crawler0-down-normals.png) | [intersections](crawler0-down-intersections.png) | [collision](crawler0-down-collision.png) | [clearance](crawler0-down-clearance.png) |
| crawler1-forward | [color](crawler1-forward-color.png) | [objects](crawler1-forward-objects.png) | [depth](crawler1-forward-depth.png) | [normals](crawler1-forward-normals.png) | [intersections](crawler1-forward-intersections.png) | [collision](crawler1-forward-collision.png) | [clearance](crawler1-forward-clearance.png) |
| crawler1-back | [color](crawler1-back-color.png) | [objects](crawler1-back-objects.png) | [depth](crawler1-back-depth.png) | [normals](crawler1-back-normals.png) | [intersections](crawler1-back-intersections.png) | [collision](crawler1-back-collision.png) | [clearance](crawler1-back-clearance.png) |
| crawler1-left | [color](crawler1-left-color.png) | [objects](crawler1-left-objects.png) | [depth](crawler1-left-depth.png) | [normals](crawler1-left-normals.png) | [intersections](crawler1-left-intersections.png) | [collision](crawler1-left-collision.png) | [clearance](crawler1-left-clearance.png) |
| crawler1-right | [color](crawler1-right-color.png) | [objects](crawler1-right-objects.png) | [depth](crawler1-right-depth.png) | [normals](crawler1-right-normals.png) | [intersections](crawler1-right-intersections.png) | [collision](crawler1-right-collision.png) | [clearance](crawler1-right-clearance.png) |
| crawler1-up | [color](crawler1-up-color.png) | [objects](crawler1-up-objects.png) | [depth](crawler1-up-depth.png) | [normals](crawler1-up-normals.png) | [intersections](crawler1-up-intersections.png) | [collision](crawler1-up-collision.png) | [clearance](crawler1-up-clearance.png) |
| crawler1-down | [color](crawler1-down-color.png) | [objects](crawler1-down-objects.png) | [depth](crawler1-down-depth.png) | [normals](crawler1-down-normals.png) | [intersections](crawler1-down-intersections.png) | [collision](crawler1-down-collision.png) | [clearance](crawler1-down-clearance.png) |
| crawler2-forward | [color](crawler2-forward-color.png) | [objects](crawler2-forward-objects.png) | [depth](crawler2-forward-depth.png) | [normals](crawler2-forward-normals.png) | [intersections](crawler2-forward-intersections.png) | [collision](crawler2-forward-collision.png) | [clearance](crawler2-forward-clearance.png) |
| crawler2-back | [color](crawler2-back-color.png) | [objects](crawler2-back-objects.png) | [depth](crawler2-back-depth.png) | [normals](crawler2-back-normals.png) | [intersections](crawler2-back-intersections.png) | [collision](crawler2-back-collision.png) | [clearance](crawler2-back-clearance.png) |
| crawler2-left | [color](crawler2-left-color.png) | [objects](crawler2-left-objects.png) | [depth](crawler2-left-depth.png) | [normals](crawler2-left-normals.png) | [intersections](crawler2-left-intersections.png) | [collision](crawler2-left-collision.png) | [clearance](crawler2-left-clearance.png) |
| crawler2-right | [color](crawler2-right-color.png) | [objects](crawler2-right-objects.png) | [depth](crawler2-right-depth.png) | [normals](crawler2-right-normals.png) | [intersections](crawler2-right-intersections.png) | [collision](crawler2-right-collision.png) | [clearance](crawler2-right-clearance.png) |
| crawler2-up | [color](crawler2-up-color.png) | [objects](crawler2-up-objects.png) | [depth](crawler2-up-depth.png) | [normals](crawler2-up-normals.png) | [intersections](crawler2-up-intersections.png) | [collision](crawler2-up-collision.png) | [clearance](crawler2-up-clearance.png) |
| crawler2-down | [color](crawler2-down-color.png) | [objects](crawler2-down-objects.png) | [depth](crawler2-down-depth.png) | [normals](crawler2-down-normals.png) | [intersections](crawler2-down-intersections.png) | [collision](crawler2-down-collision.png) | [clearance](crawler2-down-clearance.png) |
| E0437 | [color](E0437-color.png) | [objects](E0437-objects.png) | [depth](E0437-depth.png) | [normals](E0437-normals.png) | [intersections](E0437-intersections.png) | [collision](E0437-collision.png) | [clearance](E0437-clearance.png) |
| E0438 | [color](E0438-color.png) | [objects](E0438-objects.png) | [depth](E0438-depth.png) | [normals](E0438-normals.png) | [intersections](E0438-intersections.png) | [collision](E0438-collision.png) | [clearance](E0438-clearance.png) |
| E0439 | [color](E0439-color.png) | [objects](E0439-objects.png) | [depth](E0439-depth.png) | [normals](E0439-normals.png) | [intersections](E0439-intersections.png) | [collision](E0439-collision.png) | [clearance](E0439-clearance.png) |

<!-- /capture-index -->

## Findings

473 issue locations; 1220 additional locations suppressed by the report cap.

- **E0002 enemy_false_arrival** (observed), fixture:stacked-floor at [205.7507, 0.9009, 200.0]; 1 occurrence(s). See issues.json for evidence.
- **E0004 enemy_false_arrival** (observed), fixture:unreachable-goal at [198.3858, 0.9009, 199.9184]; 1 occurrence(s). See issues.json for evidence.
- **E0001 enemy_stuck** (observed), fixture:crowd-blocking at [200.8009, 0.9009, 200.0]; 1 occurrence(s). See issues.json for evidence.
- **E0003 enemy_stuck** (observed), fixture:changed-obstacle at [200.9008, 0.9009, 200.0]; 1 occurrence(s). See issues.json for evidence.
- **E0437 stuck** (observed), room:choir at [30.4555, -27.1029, 11.9925]; 2 occurrence(s). See issues.json for evidence.
- **E0438 stuck** (observed), route:first_stair at [38.1965, -6.695, -38.7031]; 1 occurrence(s). See issues.json for evidence.
- **E0439 stuck** (observed), room:first_stair_hall at [41.479, -9.0991, -39.9103]; 3 occurrence(s). See issues.json for evidence.
- **E0440 stuck** (observed), room:choir at [37.5876, -27.1012, -12.0]; 1 occurrence(s). See issues.json for evidence.
- **E0441 stuck** (observed), room:first_stair_hall at [39.9119, -9.1019, -40.443]; 2 occurrence(s). See issues.json for evidence.
- **E0442 stuck** (observed), room:ossuary at [-41.0, -9.1026, -35.5343]; 1 occurrence(s). See issues.json for evidence.
- **E0443 stuck** (observed), room:restraint at [29.4999, -3.0462, -15.352]; 2 occurrence(s). See issues.json for evidence.
- **E0444 stuck** (observed), room:restraint at [29.9847, -3.1029, -15.0661]; 1 occurrence(s). See issues.json for evidence.
- **E0445 stuck** (observed), route:chapel_approach at [18.585, -9.1019, -33.0553]; 1 occurrence(s). See issues.json for evidence.
- **E0446 stuck** (observed), room:choir at [41.5493, -27.0991, 2.5602]; 1 occurrence(s). See issues.json for evidence.
- **E0447 stuck** (observed), room:choir at [41.5499, -27.0991, 2.06]; 1 occurrence(s). See issues.json for evidence.
- **E0448 stuck** (observed), room:first_stair_hall at [35.5896, -9.0991, -28.0068]; 2 occurrence(s). See issues.json for evidence.
- **E0449 stuck** (observed), room:entry at [-42.5577, 0.9172, -28.4433]; 1 occurrence(s). See issues.json for evidence.
- **E0450 stuck** (observed), room:chapel at [2.3755, -9.0991, -41.0274]; 1 occurrence(s). See issues.json for evidence.
- **E0451 stuck** (observed), room:choir at [28.557, -27.1019, 9.5881]; 2 occurrence(s). See issues.json for evidence.
- **E0452 stuck** (observed), room:second_stair_hall at [-26.5, -22.0991, 36.4108]; 2 occurrence(s). See issues.json for evidence.
- **E0453 stuck** (observed), room:choir at [29.5, -27.1029, -7.1314]; 1 occurrence(s). See issues.json for evidence.
- **E0454 stuck** (observed), room:entry at [-37.3554, 0.8997, -30.5571]; 1 occurrence(s). See issues.json for evidence.
- **E0455 stuck** (observed), room:antechamber at [-28.0, 0.901, -25.5147]; 1 occurrence(s). See issues.json for evidence.
- **E0456 stuck** (observed), room:entry at [-35.5604, 0.9009, -29.5479]; 1 occurrence(s). See issues.json for evidence.
- **E0457 stuck** (observed), route:nave at [-25.5, -18.9431, 22.1261]; 1 occurrence(s). See issues.json for evidence.
- **E0458 stuck** (observed), room:first_stair_hall at [35.5897, -9.0991, -30.0957]; 2 occurrence(s). See issues.json for evidence.
- **E0459 stuck** (observed), room:first_stair_hall at [35.5886, -9.0997, -28.5002]; 2 occurrence(s). See issues.json for evidence.
- **E0460 stuck** (observed), room:choir at [27.5, -27.0991, 9.5892]; 2 occurrence(s). See issues.json for evidence.
- **E0461 stuck** (observed), room:choir at [27.1096, -27.0997, 9.589]; 1 occurrence(s). See issues.json for evidence.
- **E0462 stuck** (observed), room:first_stair_hall at [35.5894, -9.0991, -27.0]; 1 occurrence(s). See issues.json for evidence.
- **E0463 stuck** (observed), room:choir at [30.451, -27.099, 10.3889]; 1 occurrence(s). See issues.json for evidence.
- **E0464 stuck** (observed), route:chapel_approach at [21.552, -9.0991, -32.0879]; 1 occurrence(s). See issues.json for evidence.
- **E0465 stuck** (observed), room:choir at [41.5489, -27.0997, 0.4774]; 1 occurrence(s). See issues.json for evidence.
- **E0466 stuck** (observed), room:choir at [41.5469, -27.1023, -1.0]; 1 occurrence(s). See issues.json for evidence.
- **E0467 stuck** (observed), room:choir at [41.9101, -27.0991, -12.0]; 1 occurrence(s). See issues.json for evidence.
- **E0468 stuck** (observed), room:second_stair_hall at [-27.0, -22.0991, 25.0899]; 2 occurrence(s). See issues.json for evidence.
- **E0469 stuck** (observed), room:ossuary at [-40.0758, -9.0991, -34.8497]; 2 occurrence(s). See issues.json for evidence.
- **E0470 stuck** (observed), route:root_tunnel at [-40.1016, -22.0994, -1.8608]; 1 occurrence(s). See issues.json for evidence.
- **E0471 stuck** (observed), room:first_stair_hall at [39.911, -9.0996, -27.0]; 1 occurrence(s). See issues.json for evidence.
- **E0472 stuck** (observed), room:first_stair_hall at [41.4452, -9.0991, -28.5892]; 3 occurrence(s). See issues.json for evidence.
- **E0473 stuck** (observed), room:first_stair_hall at [40.1045, -9.0997, -28.5889]; 1 occurrence(s). See issues.json for evidence.
- **E0228 floor_collision_visual_mismatch** (candidate), route:upper_hall at [36.0, -5.044, -25.3636]; 1 occurrence(s). See issues.json for evidence.
- **E0229 floor_collision_visual_mismatch** (candidate), route:upper_hall at [36.0, -5.044, -25.8182]; 1 occurrence(s). See issues.json for evidence.
- **E0231 floor_collision_visual_mismatch** (candidate), route:upper_hall at [36.0, -6.0301, -26.7273]; 2 occurrence(s). See issues.json for evidence.
- **E0232 floor_collision_visual_mismatch** (candidate), route:upper_hall at [37.848, -6.0011, -26.7273]; 1 occurrence(s). See issues.json for evidence.
- **E0233 floor_collision_visual_mismatch** (candidate), route:upper_hall at [36.0, -6.0301, -28.0909]; 1 occurrence(s). See issues.json for evidence.
- **E0246 floor_collision_visual_mismatch** (candidate), route:nave at [-13.2906, -18.9865, 26.842]; 1 occurrence(s). See issues.json for evidence.
- **E0247 floor_collision_visual_mismatch** (candidate), route:nave at [-12.1818, -18.9933, 25.3636]; 1 occurrence(s). See issues.json for evidence.
- **E0248 floor_collision_visual_mismatch** (candidate), route:nave at [-11.073, -18.9933, 23.8852]; 2 occurrence(s). See issues.json for evidence.
- **E0249 floor_collision_visual_mismatch** (candidate), route:nave at [-13.6543, -18.9995, 26.5693]; 1 occurrence(s). See issues.json for evidence.
- **E0250 floor_collision_visual_mismatch** (candidate), route:nave at [-12.5455, -18.9981, 25.0909]; 2 occurrence(s). See issues.json for evidence.
- **E0251 floor_collision_visual_mismatch** (candidate), route:nave at [-14.0179, -19.0022, 26.2966]; 1 occurrence(s). See issues.json for evidence.
- **E0252 floor_collision_visual_mismatch** (candidate), route:nave at [-11.8003, -18.9934, 23.3398]; 2 occurrence(s). See issues.json for evidence.
- **E0253 floor_collision_visual_mismatch** (candidate), route:nave at [-12.5276, -18.9958, 22.7943]; 1 occurrence(s). See issues.json for evidence.
- **E0265 floor_collision_visual_mismatch** (candidate), route:nave at [-27.0909, -19.9833, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0328 floor_collision_visual_mismatch** (candidate), route:return_gallery at [27.3308, -10.3454, 11.68]; 2 occurrence(s). See issues.json for evidence.
- **E0337 missing_floor_candidate** (candidate), route:cave_bypass at [-47.5, -23.0, 3.5]; 1 occurrence(s). See issues.json for evidence.
- **E0338 missing_floor_candidate** (candidate), route:cave_bypass at [-47.0, -23.0, 1.5]; 1 occurrence(s). See issues.json for evidence.
- **E0339 missing_floor_candidate** (candidate), route:cave_bypass at [-46.5, -23.0, -0.5]; 1 occurrence(s). See issues.json for evidence.
- **E0340 missing_floor_candidate** (candidate), room:entry at [-46.0, 0.0, -18.0]; 1 occurrence(s). See issues.json for evidence.
- **E0341 missing_floor_candidate** (candidate), route:cave_bypass at [-46.0, -23.0, -3.0]; 2 occurrence(s). See issues.json for evidence.
- **E0342 missing_floor_candidate** (candidate), route:cave_bypass at [-46.0, -23.0, -2.0]; 1 occurrence(s). See issues.json for evidence.
- **E0343 missing_floor_candidate** (candidate), route:cave_bypass at [-45.5, -23.0, -5.0]; 2 occurrence(s). See issues.json for evidence.
- **E0344 missing_floor_candidate** (candidate), route:cave_bypass at [-45.5, -23.0, -4.0]; 1 occurrence(s). See issues.json for evidence.
- **E0345 missing_floor_candidate** (candidate), room:entry at [-45.0, 0.0, -17.5]; 1 occurrence(s). See issues.json for evidence.
- **E0346 missing_floor_candidate** (candidate), route:cave_bypass at [-45.0, -23.0, -7.0]; 4 occurrence(s). See issues.json for evidence.
- **E0347 missing_floor_candidate** (candidate), route:cave_bypass at [-45.0, -23.0, -6.0]; 2 occurrence(s). See issues.json for evidence.
- **E0348 missing_floor_candidate** (candidate), room:entry at [-44.0, 0.0, -17.0]; 1 occurrence(s). See issues.json for evidence.
- **E0349 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 14.5]; 2 occurrence(s). See issues.json for evidence.
- **E0350 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 15.5]; 2 occurrence(s). See issues.json for evidence.
- **E0351 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 16.5]; 2 occurrence(s). See issues.json for evidence.
- **E0352 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 17.5]; 2 occurrence(s). See issues.json for evidence.
- **E0353 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 18.5]; 2 occurrence(s). See issues.json for evidence.
- **E0354 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 19.5]; 2 occurrence(s). See issues.json for evidence.
- **E0355 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 20.5]; 2 occurrence(s). See issues.json for evidence.
- **E0356 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 21.5]; 2 occurrence(s). See issues.json for evidence.
- **E0357 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 22.5]; 2 occurrence(s). See issues.json for evidence.
- **E0358 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 23.5]; 3 occurrence(s). See issues.json for evidence.
- **E0359 missing_floor_candidate** (candidate), room:entry at [-43.0, 0.0, -16.5]; 1 occurrence(s). See issues.json for evidence.
- **E0360 missing_floor_candidate** (candidate), route:cave_bypass at [-43.0, -23.0, 3.5]; 2 occurrence(s). See issues.json for evidence.
- **E0361 missing_floor_candidate** (candidate), route:cave_bypass at [-42.5, -23.0, 1.0]; 1 occurrence(s). See issues.json for evidence.
- **E0362 missing_floor_candidate** (candidate), route:cave_bypass at [-42.5, -23.0, 1.5]; 1 occurrence(s). See issues.json for evidence.
- **E0363 missing_floor_candidate** (candidate), room:ossuary at [-42.0, -10.0, -28.0]; 2 occurrence(s). See issues.json for evidence.
- **E0364 missing_floor_candidate** (candidate), room:entry at [-42.0, 0.0, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0365 missing_floor_candidate** (candidate), route:cave_bypass at [-42.0, -23.0, -8.0]; 4 occurrence(s). See issues.json for evidence.
- **E0366 missing_floor_candidate** (candidate), route:cave_bypass at [-42.0, -23.0, -1.5]; 2 occurrence(s). See issues.json for evidence.
- **E0367 missing_floor_candidate** (candidate), route:cave_bypass at [-42.0, -23.0, -1.0]; 2 occurrence(s). See issues.json for evidence.
- **E0368 missing_floor_candidate** (candidate), room:ossuary at [-41.0, -10.0, -27.0]; 2 occurrence(s). See issues.json for evidence.
- **E0369 missing_floor_candidate** (candidate), room:entry at [-41.0, 0.0, -15.5]; 1 occurrence(s). See issues.json for evidence.
- **E0370 missing_floor_candidate** (candidate), room:bones at [-41.0, -10.0, -12.5]; 1 occurrence(s). See issues.json for evidence.
- **E0371 missing_floor_candidate** (candidate), route:cave_bypass at [-41.0, -23.0, -7.0]; 2 occurrence(s). See issues.json for evidence.
- **E0372 missing_floor_candidate** (candidate), route:root_tunnel at [-41.0, -23.0, 26.5]; 3 occurrence(s). See issues.json for evidence.
- **E0373 missing_floor_candidate** (candidate), room:bones at [-40.5, -10.0, -12.0]; 1 occurrence(s). See issues.json for evidence.
- **E0374 missing_floor_candidate** (candidate), room:ossuary at [-40.0, -10.0, -26.0]; 2 occurrence(s). See issues.json for evidence.
- **E0375 missing_floor_candidate** (candidate), room:entry at [-40.0, 0.0, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0376 missing_floor_candidate** (candidate), room:bones at [-40.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0377 missing_floor_candidate** (candidate), route:root_tunnel at [-40.0, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0378 missing_floor_candidate** (candidate), route:cave_bypass at [-39.5, -23.0, -6.0]; 1 occurrence(s). See issues.json for evidence.
- **E0379 missing_floor_candidate** (candidate), room:ossuary at [-39.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0380 missing_floor_candidate** (candidate), room:entry at [-39.0, 0.0, -15.5]; 1 occurrence(s). See issues.json for evidence.
- **E0381 missing_floor_candidate** (candidate), room:bones at [-39.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0382 missing_floor_candidate** (candidate), route:root_tunnel at [-39.0, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0383 missing_floor_candidate** (candidate), room:ossuary at [-38.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0384 missing_floor_candidate** (candidate), room:entry at [-38.0, 0.0, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0385 missing_floor_candidate** (candidate), room:bones at [-38.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0386 missing_floor_candidate** (candidate), route:root_tunnel at [-38.0, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0387 missing_floor_candidate** (candidate), room:ossuary at [-37.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0388 missing_floor_candidate** (candidate), room:entry at [-37.0, 0.0, -16.5]; 1 occurrence(s). See issues.json for evidence.
- **E0389 missing_floor_candidate** (candidate), room:bones at [-37.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0390 missing_floor_candidate** (candidate), route:root_tunnel at [-37.0, -23.0, 26.0]; 3 occurrence(s). See issues.json for evidence.
- **E0391 missing_floor_candidate** (candidate), route:root_tunnel at [-37.0, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0392 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 20.5]; 2 occurrence(s). See issues.json for evidence.
- **E0393 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 25.5]; 2 occurrence(s). See issues.json for evidence.
- **E0394 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0395 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 27.5]; 2 occurrence(s). See issues.json for evidence.
- **E0396 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 28.5]; 2 occurrence(s). See issues.json for evidence.
- **E0397 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 29.5]; 2 occurrence(s). See issues.json for evidence.
- **E0398 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 30.5]; 2 occurrence(s). See issues.json for evidence.
- **E0399 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 31.5]; 2 occurrence(s). See issues.json for evidence.
- **E0400 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 32.5]; 2 occurrence(s). See issues.json for evidence.
- **E0401 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 33.5]; 2 occurrence(s). See issues.json for evidence.
- **E0402 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 34.5]; 2 occurrence(s). See issues.json for evidence.
- **E0403 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 35.5]; 2 occurrence(s). See issues.json for evidence.
- **E0404 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 36.5]; 2 occurrence(s). See issues.json for evidence.
- **E0405 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 37.5]; 2 occurrence(s). See issues.json for evidence.
- **E0406 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 38.5]; 1 occurrence(s). See issues.json for evidence.
- **E0407 missing_floor_candidate** (candidate), room:entry at [-36.0, 0.0, -17.0]; 1 occurrence(s). See issues.json for evidence.
- **E0408 missing_floor_candidate** (candidate), room:bones at [-36.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0409 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0410 missing_floor_candidate** (candidate), room:entry at [-35.0, 0.0, -17.5]; 1 occurrence(s). See issues.json for evidence.
- **E0411 missing_floor_candidate** (candidate), room:bones at [-35.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0412 missing_floor_candidate** (candidate), room:second_stair_hall at [-35.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0413 missing_floor_candidate** (candidate), room:ossuary at [-34.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0414 missing_floor_candidate** (candidate), route:ossuary_loop at [-34.0, -10.0, -25.0]; 4 occurrence(s). See issues.json for evidence.
- **E0415 missing_floor_candidate** (candidate), room:entry at [-34.0, 0.0, -18.0]; 1 occurrence(s). See issues.json for evidence.
- **E0416 missing_floor_candidate** (candidate), room:bones at [-34.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0417 missing_floor_candidate** (candidate), room:second_stair_hall at [-34.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0418 missing_floor_candidate** (candidate), room:entry at [-33.5, 0.0, -19.5]; 1 occurrence(s). See issues.json for evidence.
- **E0419 missing_floor_candidate** (candidate), room:ossuary at [-33.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0420 missing_floor_candidate** (candidate), route:ossuary_loop at [-33.0, -10.0, -25.0]; 4 occurrence(s). See issues.json for evidence.
- **E0421 missing_floor_candidate** (candidate), room:entry at [-33.0, 0.0, -21.0]; 1 occurrence(s). See issues.json for evidence.
- **E0422 missing_floor_candidate** (candidate), route:entry at [-33.0, 0.0, -21.0]; 1 occurrence(s). See issues.json for evidence.
- **E0423 missing_floor_candidate** (candidate), room:bones at [-33.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0424 missing_floor_candidate** (candidate), room:second_stair_hall at [-33.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0425 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.5, -10.0, -20.5]; 1 occurrence(s). See issues.json for evidence.
- **E0426 missing_floor_candidate** (candidate), room:ossuary at [-32.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0427 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -25.0]; 3 occurrence(s). See issues.json for evidence.
- **E0428 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -24.0]; 2 occurrence(s). See issues.json for evidence.
- **E0429 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -23.0]; 2 occurrence(s). See issues.json for evidence.
- **E0430 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -22.0]; 2 occurrence(s). See issues.json for evidence.
- **E0431 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -21.0]; 2 occurrence(s). See issues.json for evidence.
- **E0432 missing_floor_candidate** (candidate), room:bones at [-32.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0433 missing_floor_candidate** (candidate), route:nave at [-32.0, -20.0, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0434 missing_floor_candidate** (candidate), route:nave at [-32.0, -20.0, 24.5]; 2 occurrence(s). See issues.json for evidence.
- **E0435 missing_floor_candidate** (candidate), room:second_stair_hall at [-32.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0436 missing_floor_candidate** (candidate), route:nave at [-31.5, -20.0, 22.5]; 1 occurrence(s). See issues.json for evidence.
- **E0007 surface_backface_candidate** (candidate), room:entry at [-46.65, 5.0, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0009 surface_backface_candidate** (candidate), room:entry at [-46.65, 5.0, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0010 surface_backface_candidate** (candidate), room:entry at [-44.65, 5.0, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0012 surface_backface_candidate** (candidate), room:entry at [-42.65, 5.0, -31.65]; 1 occurrence(s). See issues.json for evidence.
- **E0014 surface_backface_candidate** (candidate), room:entry at [-40.65, 5.0, -31.65]; 1 occurrence(s). See issues.json for evidence.
- **E0017 surface_backface_candidate** (candidate), room:entry at [-36.65, 5.0, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0018 surface_backface_candidate** (candidate), room:entry at [-33.65, 0.0, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0019 surface_backface_candidate** (candidate), room:entry at [-33.65, 5.0, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0021 surface_backface_candidate** (candidate), room:entry at [-32.65, 0.0, -28.65]; 1 occurrence(s). See issues.json for evidence.
- **E0022 surface_backface_candidate** (candidate), room:entry at [-32.65, 5.0, -28.65]; 1 occurrence(s). See issues.json for evidence.
- **E0023 surface_backface_candidate** (candidate), room:entry at [-31.65, 0.0, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0024 surface_backface_candidate** (candidate), room:entry at [-31.65, 5.0, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0027 surface_backface_candidate** (candidate), room:antechamber at [-26.65, 0.0, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0028 surface_backface_candidate** (candidate), room:antechamber at [-26.65, 7.0, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0030 surface_backface_candidate** (candidate), room:antechamber at [-24.65, 5.5388, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0031 surface_backface_candidate** (candidate), room:antechamber at [-23.65, 0.9686, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0032 surface_backface_candidate** (candidate), room:antechamber at [-23.65, 4.8425, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0037 surface_backface_candidate** (candidate), room:antechamber at [-17.65, 7.0, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0038 surface_backface_candidate** (candidate), room:antechamber at [-16.65, 0.0, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0039 surface_backface_candidate** (candidate), room:antechamber at [-16.65, 7.0, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0043 surface_backface_candidate** (candidate), room:restraint at [26.35, -0.0891, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0046 surface_backface_candidate** (candidate), room:restraint at [26.35, -1.4118, -6.65]; 1 occurrence(s). See issues.json for evidence.
- **E0047 surface_backface_candidate** (candidate), room:restraint at [27.35, -4.0, -3.65]; 1 occurrence(s). See issues.json for evidence.
- **E0048 surface_backface_candidate** (candidate), room:restraint at [27.35, 10.0, -3.65]; 1 occurrence(s). See issues.json for evidence.
- **E0049 surface_backface_candidate** (candidate), room:restraint at [28.35, -4.0, -2.65]; 1 occurrence(s). See issues.json for evidence.
- **E0050 surface_backface_candidate** (candidate), room:restraint at [28.35, 10.0, -2.65]; 1 occurrence(s). See issues.json for evidence.
- **E0052 surface_backface_candidate** (candidate), room:restraint at [30.35, 4.8444, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0055 surface_backface_candidate** (candidate), room:restraint at [33.35, -2.4906, -22.65]; 2 occurrence(s). See issues.json for evidence.
- **E0057 surface_backface_candidate** (candidate), room:restraint at [40.35, -4.0, -21.65]; 1 occurrence(s). See issues.json for evidence.
- **E0058 surface_backface_candidate** (candidate), room:restraint at [40.35, 10.0, -21.65]; 1 occurrence(s). See issues.json for evidence.
- **E0060 surface_backface_candidate** (candidate), room:restraint at [41.35, -4.0, -20.65]; 1 occurrence(s). See issues.json for evidence.
- **E0061 surface_backface_candidate** (candidate), room:restraint at [41.35, 10.0, -20.65]; 1 occurrence(s). See issues.json for evidence.
- **E0064 surface_backface_candidate** (candidate), room:cells at [30.35, -3.459, 3.35]; 1 occurrence(s). See issues.json for evidence.
- **E0068 surface_backface_candidate** (candidate), room:cells at [31.35, -4.0, 11.35]; 1 occurrence(s). See issues.json for evidence.
- **E0069 surface_backface_candidate** (candidate), room:cells at [31.35, 1.0, 11.35]; 1 occurrence(s). See issues.json for evidence.
- **E0070 surface_backface_candidate** (candidate), room:cells at [36.35, -2.497, 0.35]; 2 occurrence(s). See issues.json for evidence.
- **E0074 surface_backface_candidate** (candidate), room:cells at [41.35, -4.0, 1.35]; 1 occurrence(s). See issues.json for evidence.
- **E0075 surface_backface_candidate** (candidate), room:cells at [41.35, 1.0, 1.35]; 1 occurrence(s). See issues.json for evidence.
- **E0078 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.5357, -33.65]; 1 occurrence(s). See issues.json for evidence.
- **E0079 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.1592, -33.65]; 1 occurrence(s). See issues.json for evidence.
- **E0081 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.5416, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0082 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.1629, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0083 surface_backface_candidate** (candidate), room:chapel at [-10.65, -10.0, -24.65]; 1 occurrence(s). See issues.json for evidence.
- **E0084 surface_backface_candidate** (candidate), room:chapel at [-10.65, 6.0, -24.65]; 1 occurrence(s). See issues.json for evidence.
- **E0089 surface_backface_candidate** (candidate), room:chapel at [0.35, -1.371, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0091 surface_backface_candidate** (candidate), room:chapel at [1.35, -7.083, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0093 surface_backface_candidate** (candidate), room:chapel at [5.35, -8.5338, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0094 surface_backface_candidate** (candidate), room:chapel at [5.35, -1.7632, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0097 surface_backface_candidate** (candidate), room:chapel at [9.35, 1.369, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0100 surface_backface_candidate** (candidate), room:chapel at [11.35, -4.753, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0102 surface_backface_candidate** (candidate), room:chapel at [12.35, -7.6228, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0104 surface_backface_candidate** (candidate), room:chapel at [16.35, -10.0, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0105 surface_backface_candidate** (candidate), room:chapel at [16.35, 6.0, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0107 surface_backface_candidate** (candidate), room:chapel at [17.35, -10.0, -40.65]; 1 occurrence(s). See issues.json for evidence.
- **E0108 surface_backface_candidate** (candidate), room:chapel at [17.35, 6.0, -40.65]; 1 occurrence(s). See issues.json for evidence.
- **E0111 surface_backface_candidate** (candidate), room:nave at [-13.65, -15.4908, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0113 surface_backface_candidate** (candidate), room:nave at [-13.65, -11.6142, 30.35]; 1 occurrence(s). See issues.json for evidence.
- **E0115 surface_backface_candidate** (candidate), room:nave at [-13.65, -11.1106, 32.35]; 1 occurrence(s). See issues.json for evidence.
- **E0116 surface_backface_candidate** (candidate), room:nave at [-13.65, -17.0418, 33.35]; 1 occurrence(s). See issues.json for evidence.
- **E0118 surface_backface_candidate** (candidate), room:nave at [-13.65, -3.4791, 34.35]; 1 occurrence(s). See issues.json for evidence.
- **E0120 surface_backface_candidate** (candidate), room:nave at [-13.65, -12.5095, 35.35]; 1 occurrence(s). See issues.json for evidence.
- **E0123 surface_backface_candidate** (candidate), room:nave at [-13.65, -8.6723, 37.35]; 1 occurrence(s). See issues.json for evidence.
- **E0125 surface_backface_candidate** (candidate), room:nave at [-13.65, -10.7173, 38.35]; 1 occurrence(s). See issues.json for evidence.
- **E0129 surface_backface_candidate** (candidate), room:nave at [-13.65, -14.1826, 42.35]; 1 occurrence(s). See issues.json for evidence.
- **E0131 surface_backface_candidate** (candidate), room:nave at [-13.65, -13.204, 43.35]; 1 occurrence(s). See issues.json for evidence.
- **E0133 surface_backface_candidate** (candidate), room:nave at [-13.65, -14.5481, 44.35]; 1 occurrence(s). See issues.json for evidence.
- **E0134 surface_backface_candidate** (candidate), room:nave at [-12.65, -18.0, 47.35]; 1 occurrence(s). See issues.json for evidence.
- **E0135 surface_backface_candidate** (candidate), room:nave at [-12.65, 2.0, 47.35]; 1 occurrence(s). See issues.json for evidence.
- **E0136 surface_backface_candidate** (candidate), room:nave at [-11.65, -18.0, 48.35]; 1 occurrence(s). See issues.json for evidence.
- **E0137 surface_backface_candidate** (candidate), room:nave at [-11.65, 2.0, 48.35]; 1 occurrence(s). See issues.json for evidence.
- **E0140 surface_backface_candidate** (candidate), room:nave at [-5.65, -13.1914, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0141 surface_backface_candidate** (candidate), room:nave at [-4.65, -17.6634, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0142 surface_backface_candidate** (candidate), room:nave at [-3.65, -16.7567, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0143 surface_backface_candidate** (candidate), room:nave at [-3.65, -13.1603, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0146 surface_backface_candidate** (candidate), room:nave at [0.35, -11.5977, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0148 surface_backface_candidate** (candidate), room:nave at [3.35, -16.2503, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0150 surface_backface_candidate** (candidate), room:nave at [9.35, -16.4982, 28.35]; 2 occurrence(s). See issues.json for evidence.
- **E0151 surface_backface_candidate** (candidate), room:nave at [12.35, -18.0, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0152 surface_backface_candidate** (candidate), room:nave at [12.35, 2.0, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0153 surface_backface_candidate** (candidate), room:nave at [13.35, -18.0, 30.35]; 1 occurrence(s). See issues.json for evidence.
- **E0154 surface_backface_candidate** (candidate), room:nave at [13.35, 2.0, 30.35]; 1 occurrence(s). See issues.json for evidence.
- **E0161 surface_backface_candidate** (candidate), room:ossuary at [-41.65, -3.9098, -31.65]; 1 occurrence(s). See issues.json for evidence.
- **E0163 surface_backface_candidate** (candidate), room:ossuary at [-41.65, -5.8431, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0165 surface_backface_candidate** (candidate), room:ossuary at [-40.65, -10.0, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0166 surface_backface_candidate** (candidate), room:ossuary at [-40.65, -3.0, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0167 surface_backface_candidate** (candidate), room:ossuary at [-39.65, -10.0, -25.65]; 1 occurrence(s). See issues.json for evidence.
- **E0168 surface_backface_candidate** (candidate), room:ossuary at [-39.65, -3.0, -25.65]; 1 occurrence(s). See issues.json for evidence.
- **E0170 surface_backface_candidate** (candidate), room:ossuary at [-36.65, -7.9172, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0171 surface_backface_candidate** (candidate), room:ossuary at [-35.65, -9.4784, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0174 surface_backface_candidate** (candidate), room:ossuary at [-31.65, -9.74, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0177 surface_backface_candidate** (candidate), room:ossuary at [-27.65, -5.2674, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0179 surface_backface_candidate** (candidate), room:ossuary at [-26.65, -4.6, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0181 surface_backface_candidate** (candidate), room:ossuary at [-23.65, -10.0, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0182 surface_backface_candidate** (candidate), room:ossuary at [-23.65, -3.0, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0183 surface_backface_candidate** (candidate), room:ossuary at [-22.65, -10.0, -40.65]; 1 occurrence(s). See issues.json for evidence.
- **E0184 surface_backface_candidate** (candidate), room:ossuary at [-22.65, -3.0, -40.65]; 1 occurrence(s). See issues.json for evidence.
- **E0189 surface_backface_candidate** (candidate), room:bones at [-31.65, -8.4224, -19.65]; 2 occurrence(s). See issues.json for evidence.
- **E0192 surface_backface_candidate** (candidate), room:bones at [-29.65, -6.8438, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0199 surface_backface_candidate** (candidate), room:bones at [-23.65, -8.224, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0201 surface_backface_candidate** (candidate), room:bones at [-22.65, -6.8699, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0209 visible_ceiling_gap** (candidate), route:entry at [-19.9, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0210 visible_ceiling_gap** (candidate), route:entry at [-22.0, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0226 visible_ceiling_gap** (candidate), route:upper_hall at [24.0, -2.4, -10.0]; 2 occurrence(s). See issues.json for evidence.
- **E0227 visible_ceiling_gap** (candidate), route:upper_hall at [24.9524, -2.4, -9.8571]; 2 occurrence(s). See issues.json for evidence.
- **E0254 visible_ceiling_gap** (candidate), route:nave at [-14.0, -17.4, 24.0]; 2 occurrence(s). See issues.json for evidence.
- **E0259 visible_ceiling_gap** (candidate), route:nave at [-17.8788, -17.6424, 25.848]; 2 occurrence(s). See issues.json for evidence.
- **E0261 visible_ceiling_gap** (candidate), route:nave at [-20.303, -17.7939, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0275 visible_ceiling_gap** (candidate), route:root_tunnel at [-39.2349, -21.4, 9.8986]; 2 occurrence(s). See issues.json for evidence.
- **E0277 visible_ceiling_gap** (candidate), route:root_tunnel at [-38.4657, -21.4, 9.2833]; 1 occurrence(s). See issues.json for evidence.
- **E0329 visible_ceiling_gap** (candidate), route:return_gallery at [21.913, -8.4, 9.0435]; 1 occurrence(s). See issues.json for evidence.
- **E0330 visible_ceiling_gap** (candidate), route:return_gallery at [20.7407, -8.4, -4.3704]; 1 occurrence(s). See issues.json for evidence.
- **E0331 visible_ceiling_gap** (candidate), route:return_gallery at [20.5185, -8.4, -7.2593]; 1 occurrence(s). See issues.json for evidence.
- **E0332 visible_ceiling_gap** (candidate), route:ossuary_loop at [-18.0, -8.4, -15.5]; 1 occurrence(s). See issues.json for evidence.
- **E0333 visible_ceiling_gap** (candidate), route:ossuary_loop at [-15.0, -8.4, -36.0]; 1 occurrence(s). See issues.json for evidence.
- **E0334 visible_ceiling_gap** (candidate), route:cave_bypass at [-45.038, -21.4, 11.5985]; 1 occurrence(s). See issues.json for evidence.
- **E0335 visible_ceiling_gap** (candidate), route:cave_bypass at [-46.9527, -21.4, 2.7232]; 1 occurrence(s). See issues.json for evidence.
- **E0336 visible_ceiling_gap** (candidate), route:cave_bypass at [-46.8416, -21.4, 2.2417]; 1 occurrence(s). See issues.json for evidence.
- **E0205 visible_floor_gap** (candidate), route:entry at [-29.9805, 1.6, -21.1893]; 1 occurrence(s). See issues.json for evidence.
- **E0206 visible_floor_gap** (candidate), route:entry at [-29.3714, 1.6, -23.2571]; 1 occurrence(s). See issues.json for evidence.
- **E0207 visible_floor_gap** (candidate), route:entry at [-29.4947, 1.6, -21.1608]; 1 occurrence(s). See issues.json for evidence.
- **E0208 visible_floor_gap** (candidate), route:entry at [-19.9, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0211 visible_floor_gap** (candidate), route:high_span at [-18.1905, 1.3333, -15.2381]; 1 occurrence(s). See issues.json for evidence.
- **E0212 visible_floor_gap** (candidate), route:high_span at [-16.2857, 1.2, -14.8571]; 2 occurrence(s). See issues.json for evidence.
- **E0213 visible_floor_gap** (candidate), route:high_span at [-14.381, 1.0667, -14.4762]; 1 occurrence(s). See issues.json for evidence.
- **E0214 visible_floor_gap** (candidate), route:high_span at [-12.0, 0.9, -14.0]; 2 occurrence(s). See issues.json for evidence.
- **E0215 visible_floor_gap** (candidate), route:high_span at [-6.7895, 0.4947, -12.8421]; 1 occurrence(s). See issues.json for evidence.
- **E0216 visible_floor_gap** (candidate), route:high_span at [-5.3684, 0.3842, -12.5263]; 1 occurrence(s). See issues.json for evidence.
- **E0217 visible_floor_gap** (candidate), route:high_span at [-3.0, 0.2, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0218 visible_floor_gap** (candidate), route:high_span at [0.0, -0.1, -13.5]; 1 occurrence(s). See issues.json for evidence.
- **E0219 visible_floor_gap** (candidate), route:high_span at [3.0, -0.4, -15.0]; 2 occurrence(s). See issues.json for evidence.
- **E0220 visible_floor_gap** (candidate), route:high_span at [5.4, -0.6, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0221 visible_floor_gap** (candidate), route:high_span at [7.8, -0.8, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0222 visible_floor_gap** (candidate), route:high_span at [10.2, -1.0, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0223 visible_floor_gap** (candidate), route:high_span at [12.6, -1.2, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0224 visible_floor_gap** (candidate), route:high_span at [14.52, -1.36, -15.0]; 3 occurrence(s). See issues.json for evidence.
- **E0225 visible_floor_gap** (candidate), route:high_span at [18.4286, -1.781, -13.0952]; 1 occurrence(s). See issues.json for evidence.
- **E0230 visible_floor_gap** (candidate), route:upper_hall at [37.848, -3.3091, -26.2727]; 1 occurrence(s). See issues.json for evidence.
- **E0234 visible_floor_gap** (candidate), route:chapel_approach at [25.8095, -8.4, -29.619]; 1 occurrence(s). See issues.json for evidence.
- **E0235 visible_floor_gap** (candidate), route:chapel_approach at [24.1971, -8.4, -27.9231]; 1 occurrence(s). See issues.json for evidence.
- **E0236 visible_floor_gap** (candidate), route:chapel_approach at [24.381, -8.4, -29.7619]; 1 occurrence(s). See issues.json for evidence.
- **E0237 visible_floor_gap** (candidate), route:central_ledge at [7.0, -16.4, 21.0]; 1 occurrence(s). See issues.json for evidence.
- **E0238 visible_floor_gap** (candidate), route:nave at [7.0, -16.4, 21.0]; 1 occurrence(s). See issues.json for evidence.
- **E0239 visible_floor_gap** (candidate), route:nave at [7.0, -16.4, 21.5]; 1 occurrence(s). See issues.json for evidence.
- **E0240 visible_floor_gap** (candidate), route:nave at [7.0, -16.4, 24.5]; 1 occurrence(s). See issues.json for evidence.
- **E0241 visible_floor_gap** (candidate), route:nave at [5.152, -16.4, 24.5]; 1 occurrence(s). See issues.json for evidence.
- **E0242 visible_floor_gap** (candidate), route:nave at [-11.848, -16.4, 27.0]; 1 occurrence(s). See issues.json for evidence.
- **E0243 visible_floor_gap** (candidate), route:nave at [-10.3636, -16.4909, 26.7273]; 1 occurrence(s). See issues.json for evidence.
- **E0244 visible_floor_gap** (candidate), route:nave at [-9.2548, -16.4909, 25.2489]; 1 occurrence(s). See issues.json for evidence.
- **E0245 visible_floor_gap** (candidate), route:nave at [-11.4545, -16.7636, 25.9091]; 1 occurrence(s). See issues.json for evidence.
- **E0255 visible_floor_gap** (candidate), route:nave at [-14.9697, -17.4606, 22.152]; 1 occurrence(s). See issues.json for evidence.
- **E0256 visible_floor_gap** (candidate), route:nave at [-17.3939, -17.6121, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0257 visible_floor_gap** (candidate), route:nave at [-17.3939, -17.6121, 22.152]; 1 occurrence(s). See issues.json for evidence.
- **E0258 visible_floor_gap** (candidate), route:nave at [-17.8788, -17.6424, 25.848]; 2 occurrence(s). See issues.json for evidence.
- **E0260 visible_floor_gap** (candidate), route:nave at [-19.3333, -17.7333, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0262 visible_floor_gap** (candidate), route:nave at [-20.7879, -17.8242, 22.152]; 1 occurrence(s). See issues.json for evidence.
- **E0263 visible_floor_gap** (candidate), route:nave at [-26.1212, -18.1576, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0264 visible_floor_gap** (candidate), route:nave at [-26.6061, -18.1879, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0266 visible_floor_gap** (candidate), route:root_tunnel at [-37.5, -21.4, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0267 visible_floor_gap** (candidate), route:root_tunnel at [-37.5, -21.4, 21.9]; 1 occurrence(s). See issues.json for evidence.
- **E0268 visible_floor_gap** (candidate), route:root_tunnel at [-41.0, -21.4, 23.5]; 1 occurrence(s). See issues.json for evidence.
- **E0269 visible_floor_gap** (candidate), route:root_tunnel at [-43.1, -21.4, 19.0]; 2 occurrence(s). See issues.json for evidence.
- **E0270 visible_floor_gap** (candidate), route:root_tunnel at [-40.6154, -21.4, 13.6923]; 1 occurrence(s). See issues.json for evidence.
- **E0271 visible_floor_gap** (candidate), route:root_tunnel at [-40.7734, -21.4, 11.1294]; 1 occurrence(s). See issues.json for evidence.
- **E0272 visible_floor_gap** (candidate), route:root_tunnel at [-38.6923, -21.4, 12.1538]; 1 occurrence(s). See issues.json for evidence.
- **E0273 visible_floor_gap** (candidate), route:root_tunnel at [-38.3077, -21.4, 11.8462]; 1 occurrence(s). See issues.json for evidence.
- **E0274 visible_floor_gap** (candidate), route:root_tunnel at [-39.2349, -21.4, 9.8986]; 2 occurrence(s). See issues.json for evidence.
- **E0276 visible_floor_gap** (candidate), route:root_tunnel at [-38.4657, -21.4, 9.2833]; 1 occurrence(s). See issues.json for evidence.
- **E0278 visible_floor_gap** (candidate), route:root_tunnel at [-32.9231, -21.4, 7.5385]; 1 occurrence(s). See issues.json for evidence.
- **E0279 visible_floor_gap** (candidate), route:root_tunnel at [-32.5385, -21.4, 7.2308]; 1 occurrence(s). See issues.json for evidence.
- **E0280 visible_floor_gap** (candidate), route:root_tunnel at [-34.4895, -21.4, 5.201]; 1 occurrence(s). See issues.json for evidence.
- **E0281 visible_floor_gap** (candidate), route:root_tunnel at [-32.9091, -21.4, 3.8182]; 1 occurrence(s). See issues.json for evidence.
- **E0282 visible_floor_gap** (candidate), route:root_tunnel at [-31.3287, -21.4, 2.4353]; 1 occurrence(s). See issues.json for evidence.
- **E0283 visible_floor_gap** (candidate), route:root_tunnel at [-36.1014, -21.4, -3.0192]; 1 occurrence(s). See issues.json for evidence.
- **E0284 visible_floor_gap** (candidate), route:root_tunnel at [-37.4195, -21.4, -5.1775]; 1 occurrence(s). See issues.json for evidence.
- **E0285 visible_floor_gap** (candidate), route:root_tunnel at [-33.2472, -21.4, -3.1559]; 1 occurrence(s). See issues.json for evidence.
- **E0286 visible_floor_gap** (candidate), route:root_tunnel at [-34.7528, -21.4, -7.3441]; 1 occurrence(s). See issues.json for evidence.
- **E0287 visible_floor_gap** (candidate), route:root_tunnel at [-32.1043, -21.4, -4.0844]; 1 occurrence(s). See issues.json for evidence.
- **E0288 visible_floor_gap** (candidate), route:root_tunnel at [-27.0, -21.4, -11.7143]; 2 occurrence(s). See issues.json for evidence.
- **E0289 visible_floor_gap** (candidate), route:root_tunnel at [-26.3333, -21.4, -12.4286]; 1 occurrence(s). See issues.json for evidence.
- **E0290 visible_floor_gap** (candidate), route:root_tunnel at [-26.5352, -21.4, -15.29]; 1 occurrence(s). See issues.json for evidence.
- **E0291 visible_floor_gap** (candidate), route:root_tunnel at [-25.0, -21.4, -13.8571]; 1 occurrence(s). See issues.json for evidence.
- **E0292 visible_floor_gap** (candidate), route:root_tunnel at [-23.3333, -21.4, -15.6429]; 2 occurrence(s). See issues.json for evidence.
- **E0293 visible_floor_gap** (candidate), route:low_span at [-23.0, -21.4, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0294 visible_floor_gap** (candidate), route:low_span at [-20.6316, -21.6632, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0295 visible_floor_gap** (candidate), route:low_span at [-19.6842, -21.7684, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0296 visible_floor_gap** (candidate), route:low_span at [-17.3158, -22.0316, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0297 visible_floor_gap** (candidate), route:low_span at [-16.3684, -22.1368, -16.0]; 2 occurrence(s). See issues.json for evidence.
- **E0298 visible_floor_gap** (candidate), route:low_span at [-14.9474, -22.2947, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0299 visible_floor_gap** (candidate), route:low_span at [-14.0, -22.4, -16.0]; 2 occurrence(s). See issues.json for evidence.
- **E0300 visible_floor_gap** (candidate), route:low_span at [-11.1053, -22.6895, -11.3684]; 1 occurrence(s). See issues.json for evidence.
- **E0301 visible_floor_gap** (candidate), route:low_span at [-9.7895, -22.8211, -9.2632]; 1 occurrence(s). See issues.json for evidence.
- **E0302 visible_floor_gap** (candidate), route:low_span at [-9.0, -22.9, -8.0]; 2 occurrence(s). See issues.json for evidence.
- **E0303 visible_floor_gap** (candidate), route:low_span at [-8.3333, -22.9556, -6.6667]; 1 occurrence(s). See issues.json for evidence.
- **E0304 visible_floor_gap** (candidate), route:low_span at [-7.6667, -23.0111, -5.3333]; 1 occurrence(s). See issues.json for evidence.
- **E0305 visible_floor_gap** (candidate), route:low_span at [-7.0, -23.0667, -4.0]; 1 occurrence(s). See issues.json for evidence.
- **E0306 visible_floor_gap** (candidate), route:low_span at [-6.3333, -23.1222, -2.6667]; 1 occurrence(s). See issues.json for evidence.
- **E0307 visible_floor_gap** (candidate), route:low_span at [-5.6667, -23.1778, -1.3333]; 1 occurrence(s). See issues.json for evidence.
- **E0308 visible_floor_gap** (candidate), route:low_span at [-5.4444, -23.1963, -0.8889]; 1 occurrence(s). See issues.json for evidence.
- **E0309 visible_floor_gap** (candidate), route:low_span at [-5.0, -23.2333, 0.0]; 1 occurrence(s). See issues.json for evidence.
- **E0310 visible_floor_gap** (candidate), route:low_span at [-4.3333, -23.2889, 1.3333]; 1 occurrence(s). See issues.json for evidence.
- **E0311 visible_floor_gap** (candidate), route:low_span at [-3.6667, -23.3444, 2.6667]; 1 occurrence(s). See issues.json for evidence.
- **E0312 visible_floor_gap** (candidate), route:low_span at [-3.0, -23.4, 4.0]; 2 occurrence(s). See issues.json for evidence.
- **E0313 visible_floor_gap** (candidate), route:low_span at [-1.7368, -23.5579, 4.7895]; 1 occurrence(s). See issues.json for evidence.
- **E0314 visible_floor_gap** (candidate), route:low_span at [0.3684, -23.8211, 6.1053]; 1 occurrence(s). See issues.json for evidence.
- **E0315 visible_floor_gap** (candidate), route:low_span at [1.6316, -23.9789, 6.8947]; 1 occurrence(s). See issues.json for evidence.
- **E0316 visible_floor_gap** (candidate), route:low_span at [5.0, -24.4, 9.0]; 2 occurrence(s). See issues.json for evidence.
- **E0317 visible_floor_gap** (candidate), route:low_span at [4.7862, -24.4, 7.5032]; 1 occurrence(s). See issues.json for evidence.
- **E0318 visible_floor_gap** (candidate), route:low_span at [7.3333, -24.7333, 8.6667]; 1 occurrence(s). See issues.json for evidence.
- **E0319 visible_floor_gap** (candidate), route:low_span at [8.2667, -24.8667, 8.5333]; 1 occurrence(s). See issues.json for evidence.
- **E0320 visible_floor_gap** (candidate), route:low_span at [9.6667, -25.0667, 8.3333]; 2 occurrence(s). See issues.json for evidence.
- **E0321 visible_floor_gap** (candidate), route:low_span at [12.0, -25.4, 8.0]; 2 occurrence(s). See issues.json for evidence.
- **E0322 visible_floor_gap** (candidate), route:low_span at [13.5385, -25.5154, 6.0769]; 1 occurrence(s). See issues.json for evidence.
- **E0323 visible_floor_gap** (candidate), route:low_span at [14.4615, -25.5846, 4.9231]; 1 occurrence(s). See issues.json for evidence.
- **E0324 visible_floor_gap** (candidate), route:low_span at [16.0, -25.7, 3.0]; 2 occurrence(s). See issues.json for evidence.
- **E0325 visible_floor_gap** (candidate), route:low_span at [15.9719, -25.735, 4.5844]; 1 occurrence(s). See issues.json for evidence.
- **E0326 visible_floor_gap** (candidate), route:low_span at [17.8, -25.84, 3.6]; 2 occurrence(s). See issues.json for evidence.
- **E0327 visible_floor_gap** (candidate), route:low_span at [20.5, -26.05, 4.5]; 1 occurrence(s). See issues.json for evidence.
- **E0005 raised_render_surface** (candidate), room:entry at [-47.65, 0.2764, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0006 raised_render_surface** (candidate), room:entry at [-47.65, 0.2763, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0008 raised_render_surface** (candidate), room:entry at [-46.65, 0.2821, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0011 raised_render_surface** (candidate), room:entry at [-44.65, 0.2817, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0013 raised_render_surface** (candidate), room:entry at [-42.65, 0.2842, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0015 raised_render_surface** (candidate), room:entry at [-40.65, 0.2793, -15.65]; 1 occurrence(s). See issues.json for evidence.
- **E0016 raised_render_surface** (candidate), room:entry at [-37.65, 0.2858, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0020 raised_render_surface** (candidate), room:entry at [-33.65, 0.2799, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0025 raised_render_surface** (candidate), room:antechamber at [-27.65, 0.2831, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0026 raised_render_surface** (candidate), room:antechamber at [-27.65, 0.28, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0029 raised_render_surface** (candidate), room:antechamber at [-24.65, 0.281, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0033 raised_render_surface** (candidate), room:antechamber at [-22.65, 0.2912, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0034 raised_render_surface** (candidate), room:antechamber at [-21.65, 0.2895, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0035 raised_render_surface** (candidate), room:antechamber at [-20.65, 0.2833, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0036 raised_render_surface** (candidate), room:antechamber at [-19.65, 0.282, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0040 raised_render_surface** (candidate), room:antechamber at [-16.65, 0.2905, -18.65]; 1 occurrence(s). See issues.json for evidence.
- **E0041 raised_render_surface** (candidate), room:restraint at [26.35, -3.7188, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0042 raised_render_surface** (candidate), room:restraint at [26.35, -3.7195, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0044 raised_render_surface** (candidate), room:restraint at [26.35, -3.7149, -12.65]; 1 occurrence(s). See issues.json for evidence.
- **E0045 raised_render_surface** (candidate), room:restraint at [26.35, -3.7158, -6.65]; 1 occurrence(s). See issues.json for evidence.
- **E0051 raised_render_surface** (candidate), room:restraint at [30.35, -3.712, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0053 raised_render_surface** (candidate), room:restraint at [31.35, -3.7122, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0054 raised_render_surface** (candidate), room:restraint at [32.35, -3.7169, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0056 raised_render_surface** (candidate), room:restraint at [39.35, -3.7148, -2.65]; 1 occurrence(s). See issues.json for evidence.
- **E0059 raised_render_surface** (candidate), room:restraint at [40.35, -3.7183, -3.65]; 1 occurrence(s). See issues.json for evidence.
- **E0062 raised_render_surface** (candidate), room:restraint at [41.35, -3.8274, -4.65]; 1 occurrence(s). See issues.json for evidence.
- **E0063 raised_render_surface** (candidate), room:cells at [30.35, -3.7167, 2.35]; 1 occurrence(s). See issues.json for evidence.
- **E0065 raised_render_surface** (candidate), room:cells at [30.35, -3.721, 4.35]; 1 occurrence(s). See issues.json for evidence.
- **E0066 raised_render_surface** (candidate), room:cells at [30.35, -3.7135, 5.35]; 1 occurrence(s). See issues.json for evidence.
- **E0067 raised_render_surface** (candidate), room:cells at [30.35, -3.7197, 6.35]; 1 occurrence(s). See issues.json for evidence.
- **E0071 raised_render_surface** (candidate), room:cells at [37.35, -3.7107, 0.35]; 1 occurrence(s). See issues.json for evidence.
- **E0072 raised_render_surface** (candidate), room:cells at [38.35, -3.7193, 0.35]; 1 occurrence(s). See issues.json for evidence.
- **E0073 raised_render_surface** (candidate), room:cells at [40.35, -3.7168, 11.35]; 1 occurrence(s). See issues.json for evidence.
- **E0076 raised_render_surface** (candidate), room:cells at [41.35, -3.7227, 10.35]; 1 occurrence(s). See issues.json for evidence.
- **E0077 raised_render_surface** (candidate), room:chapel at [-11.65, -8.5521, -38.65]; 1 occurrence(s). See issues.json for evidence.
- **E0080 raised_render_surface** (candidate), room:chapel at [-11.65, -8.5573, -32.65]; 1 occurrence(s). See issues.json for evidence.
- **E0085 raised_render_surface** (candidate), room:chapel at [-7.65, -9.6375, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0086 raised_render_surface** (candidate), room:chapel at [-6.65, -9.6402, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0087 raised_render_surface** (candidate), room:chapel at [-4.65, -9.6239, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0088 raised_render_surface** (candidate), room:chapel at [0.35, -9.6388, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0090 raised_render_surface** (candidate), room:chapel at [1.35, -9.6404, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0092 raised_render_surface** (candidate), room:chapel at [4.35, -9.6333, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0095 raised_render_surface** (candidate), room:chapel at [8.35, -9.6416, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0096 raised_render_surface** (candidate), room:chapel at [9.35, -9.6418, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0098 raised_render_surface** (candidate), room:chapel at [10.35, -9.6338, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0099 raised_render_surface** (candidate), room:chapel at [11.35, -9.6375, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0101 raised_render_surface** (candidate), room:chapel at [12.35, -9.6333, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0103 raised_render_surface** (candidate), room:chapel at [15.35, -9.6308, -24.65]; 1 occurrence(s). See issues.json for evidence.
- **E0106 raised_render_surface** (candidate), room:chapel at [16.35, -9.6378, -25.65]; 1 occurrence(s). See issues.json for evidence.
- **E0109 raised_render_surface** (candidate), room:chapel at [17.35, -9.6295, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0110 raised_render_surface** (candidate), room:nave at [-13.65, -17.6762, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0112 raised_render_surface** (candidate), room:nave at [-13.65, -17.6707, 30.35]; 1 occurrence(s). See issues.json for evidence.
- **E0114 raised_render_surface** (candidate), room:nave at [-13.65, -16.8031, 32.35]; 1 occurrence(s). See issues.json for evidence.
- **E0117 raised_render_surface** (candidate), room:nave at [-13.65, -17.6751, 34.35]; 1 occurrence(s). See issues.json for evidence.
- **E0119 raised_render_surface** (candidate), room:nave at [-13.65, -17.6752, 35.35]; 1 occurrence(s). See issues.json for evidence.
- **E0121 raised_render_surface** (candidate), room:nave at [-13.65, -17.393, 36.35]; 1 occurrence(s). See issues.json for evidence.
- **E0122 raised_render_surface** (candidate), room:nave at [-13.65, -17.6748, 37.35]; 1 occurrence(s). See issues.json for evidence.
- **E0124 raised_render_surface** (candidate), room:nave at [-13.65, -17.6664, 38.35]; 1 occurrence(s). See issues.json for evidence.
- **E0126 raised_render_surface** (candidate), room:nave at [-13.65, -17.6812, 39.35]; 1 occurrence(s). See issues.json for evidence.
- **E0127 raised_render_surface** (candidate), room:nave at [-13.65, -17.6761, 40.35]; 1 occurrence(s). See issues.json for evidence.
- **E0128 raised_render_surface** (candidate), room:nave at [-13.65, -17.6757, 42.35]; 1 occurrence(s). See issues.json for evidence.
- **E0130 raised_render_surface** (candidate), room:nave at [-13.65, -17.675, 43.35]; 1 occurrence(s). See issues.json for evidence.
- **E0132 raised_render_surface** (candidate), room:nave at [-13.65, -17.6749, 44.35]; 1 occurrence(s). See issues.json for evidence.
- **E0138 raised_render_surface** (candidate), room:nave at [-6.65, -17.6785, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0139 raised_render_surface** (candidate), room:nave at [-5.65, -17.6751, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0144 raised_render_surface** (candidate), room:nave at [-0.65, -17.6723, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0145 raised_render_surface** (candidate), room:nave at [0.35, -17.6696, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0147 raised_render_surface** (candidate), room:nave at [3.35, -17.6707, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0149 raised_render_surface** (candidate), room:nave at [4.35, -16.513, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0155 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.5217, -38.65]; 1 occurrence(s). See issues.json for evidence.
- **E0156 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7671, -37.65]; 1 occurrence(s). See issues.json for evidence.
- **E0157 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7583, -36.65]; 1 occurrence(s). See issues.json for evidence.
- **E0158 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7628, -35.65]; 1 occurrence(s). See issues.json for evidence.
- **E0159 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.758, -32.65]; 1 occurrence(s). See issues.json for evidence.
- **E0160 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7621, -31.65]; 1 occurrence(s). See issues.json for evidence.
- **E0162 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.75, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0164 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7623, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0169 raised_render_surface** (candidate), room:ossuary at [-36.65, -9.7656, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0172 raised_render_surface** (candidate), room:ossuary at [-34.65, -9.7608, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0173 raised_render_surface** (candidate), room:ossuary at [-32.65, -9.7651, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0175 raised_render_surface** (candidate), room:ossuary at [-28.65, -9.765, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0176 raised_render_surface** (candidate), room:ossuary at [-27.65, -9.7593, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0178 raised_render_surface** (candidate), room:ossuary at [-26.65, -9.7637, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0180 raised_render_surface** (candidate), room:ossuary at [-24.65, -9.7584, -25.65]; 1 occurrence(s). See issues.json for evidence.
- **E0185 raised_render_surface** (candidate), room:bones at [-41.65, -9.6802, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0186 raised_render_surface** (candidate), room:bones at [-38.65, -9.6825, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0187 raised_render_surface** (candidate), room:bones at [-37.65, -9.678, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0188 raised_render_surface** (candidate), room:bones at [-36.65, -8.4235, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0190 raised_render_surface** (candidate), room:bones at [-30.65, -9.6778, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0191 raised_render_surface** (candidate), room:bones at [-29.65, -9.6812, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0193 raised_render_surface** (candidate), room:bones at [-28.65, -9.6803, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0194 raised_render_surface** (candidate), room:bones at [-27.65, -9.6848, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0195 raised_render_surface** (candidate), room:bones at [-26.65, -9.6862, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0196 raised_render_surface** (candidate), room:bones at [-25.65, -9.3496, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0197 raised_render_surface** (candidate), room:bones at [-24.65, -9.6764, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0198 raised_render_surface** (candidate), room:bones at [-23.65, -9.6868, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0200 raised_render_surface** (candidate), room:bones at [-22.65, -9.6836, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0202 raised_render_surface** (candidate), room:bones at [-21.65, -8.716, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0203 raised_render_surface** (candidate), room:window at [-27.15, -9.7155, -8.65]; 1 occurrence(s). See issues.json for evidence.
- **E0204 raised_render_surface** (candidate), room:window at [-27.15, -9.7265, -7.65]; 1 occurrence(s). See issues.json for evidence.
