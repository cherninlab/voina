# Dungeon explorer run

Build `89bc19d04e15d21a6dc673ef354a3a9e5b09c44d`; seed 186; mode full.

Actual capsule visits: 17236 / 21616 sampled walkable cells.
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
| room:antechamber | 528 | 548 |
| room:bell | 669 | 1348 |
| room:bones | 567 | 567 |
| room:cells | 459 | 495 |
| room:chapel | 1529 | 2050 |
| room:choir | 967 | 2450 |
| room:entry | 712 | 712 |
| room:first_stair_hall | 438 | 639 |
| room:nave | 1520 | 2152 |
| room:ossuary | 1069 | 1222 |
| room:restraint | 1108 | 1153 |
| room:second_stair_hall | 398 | 398 |
| room:window | 368 | 368 |
| route:bell_loop | 310 | 322 |
| route:cave_bypass | 376 | 378 |
| route:central_ledge | 596 | 615 |
| route:chapel_approach | 139 | 139 |
| route:choir | 2 | 2 |
| route:entry | 89 | 89 |
| route:first_stair | 385 | 385 |
| route:high_span | 433 | 433 |
| route:low_span | 637 | 637 |
| route:nave | 391 | 391 |
| route:ossuary_loop | 495 | 555 |
| route:return_gallery | 561 | 647 |
| route:return_stair | 511 | 942 |
| route:root_tunnel | 1077 | 1077 |
| route:second_stair | 353 | 353 |
| route:upper_cells | 439 | 439 |
| route:upper_hall | 110 | 110 |

## Gameplay bot scenarios

| Scenario | Arrived | False arrival | Longest stuck (s) |
| --- | --- | --- | ---: |
| clear-floor | True | False | 0.0166666666666667 |
| crowd-blocking | True | False | 0.65 |
| actor-obstruction-removed | True | False | 0.0166666666666667 |
| stacked-floor | False | False | 1.46666666666667 |
| changed-obstacle | True | False | 0.583333333333333 |
| static-detour | True | False | 0.0166666666666667 |
| unreachable-goal | False | False | 2.0 |
| cover-memory-reacquire-return | see trace | see trace | see trace |
| dungeon-hall-0 | True | False | 0.0166666666666667 |
| dungeon-hall-2 | True | False | 0.0166666666666667 |

Detector controls: 22/22 passed.

Travel estimates and unchecked directions are in travel-times.json. They sum observed edge times and are not single-trip timings.

## Findings

418 issue locations; 1090 additional locations suppressed by the report cap.

- **E0001 enemy_stuck** (observed), fixture:unreachable-goal at [198.3291, 0.9009, 199.8741]; 1 occurrence(s). See issues.json for evidence.
- **E0386 stuck** (observed), room:first_stair_hall at [35.589, -9.0996, -29.5]; 2 occurrence(s). See issues.json for evidence.
- **E0387 stuck** (observed), room:first_stair_hall at [35.5898, -9.0991, -28.5205]; 2 occurrence(s). See issues.json for evidence.
- **E0388 stuck** (observed), room:first_stair_hall at [35.5899, -9.0991, -27.0]; 1 occurrence(s). See issues.json for evidence.
- **E0389 stuck** (observed), room:entry at [-35.5, 0.8985, -29.5313]; 1 occurrence(s). See issues.json for evidence.
- **E0390 stuck** (observed), room:entry at [-37.5001, 0.9787, -30.0327]; 1 occurrence(s). See issues.json for evidence.
- **E0391 stuck** (observed), room:restraint at [29.5071, -3.0457, -15.3558]; 3 occurrence(s). See issues.json for evidence.
- **E0392 stuck** (observed), room:restraint at [29.0926, -3.0691, -15.1072]; 1 occurrence(s). See issues.json for evidence.
- **E0393 stuck** (observed), room:first_stair_hall at [39.9102, -9.0991, -40.0205]; 4 occurrence(s). See issues.json for evidence.
- **E0394 stuck** (observed), room:first_stair_hall at [40.8955, -9.0997, -39.9111]; 2 occurrence(s). See issues.json for evidence.
- **E0395 stuck** (observed), room:cells at [31.0589, -3.0991, 9.4259]; 1 occurrence(s). See issues.json for evidence.
- **E0396 stuck** (observed), route:second_stair at [-33.198, -20.9408, 34.7538]; 2 occurrence(s). See issues.json for evidence.
- **E0397 stuck** (observed), room:antechamber at [-28.0, 0.901, -25.5145]; 1 occurrence(s). See issues.json for evidence.
- **E0398 stuck** (observed), route:first_stair at [38.0492, -6.6971, -38.5668]; 1 occurrence(s). See issues.json for evidence.
- **E0399 stuck** (observed), room:choir at [41.5489, -27.0997, -2.0]; 2 occurrence(s). See issues.json for evidence.
- **E0400 stuck** (observed), room:choir at [41.5469, -27.1023, -3.0]; 2 occurrence(s). See issues.json for evidence.
- **E0401 stuck** (observed), room:second_stair_hall at [-26.5, -22.0991, 36.4108]; 2 occurrence(s). See issues.json for evidence.
- **E0402 stuck** (observed), room:first_stair_hall at [35.5876, -9.1013, -28.0]; 2 occurrence(s). See issues.json for evidence.
- **E0403 stuck** (observed), room:choir at [41.5489, -27.0997, 2.5]; 2 occurrence(s). See issues.json for evidence.
- **E0404 stuck** (observed), room:choir at [41.5489, -27.0997, 4.5]; 1 occurrence(s). See issues.json for evidence.
- **E0405 stuck** (observed), room:choir at [28.9452, -27.0991, 9.5892]; 1 occurrence(s). See issues.json for evidence.
- **E0406 stuck** (observed), room:choir at [28.0078, -27.0991, 9.589]; 3 occurrence(s). See issues.json for evidence.
- **E0407 stuck** (observed), route:nave at [-25.5, -18.9431, 22.1261]; 1 occurrence(s). See issues.json for evidence.
- **E0408 stuck** (observed), room:choir at [41.9101, -27.0991, -12.0]; 1 occurrence(s). See issues.json for evidence.
- **E0409 stuck** (observed), room:second_stair_hall at [-26.9452, -22.0991, 25.0892]; 2 occurrence(s). See issues.json for evidence.
- **E0410 stuck** (observed), room:choir at [37.5892, -27.0991, -11.5548]; 1 occurrence(s). See issues.json for evidence.
- **E0411 stuck** (observed), room:first_stair_hall at [39.9111, -9.0997, -40.8955]; 1 occurrence(s). See issues.json for evidence.
- **E0412 stuck** (observed), room:entry at [-37.3554, 0.8997, -30.5571]; 1 occurrence(s). See issues.json for evidence.
- **E0413 stuck** (observed), room:ossuary at [-40.0701, -9.0991, -35.0]; 2 occurrence(s). See issues.json for evidence.
- **E0414 stuck** (observed), room:first_stair_hall at [40.0, -9.0991, -28.5892]; 1 occurrence(s). See issues.json for evidence.
- **E0415 stuck** (observed), room:first_stair_hall at [41.443, -9.1019, -28.5881]; 3 occurrence(s). See issues.json for evidence.
- **E0416 stuck** (observed), room:ossuary at [-40.9999, -9.0991, -35.5312]; 2 occurrence(s). See issues.json for evidence.
- **E0417 stuck** (observed), room:choir at [41.5489, -27.0997, 2.0]; 1 occurrence(s). See issues.json for evidence.
- **E0418 stuck** (observed), room:choir at [41.5469, -27.1023, 1.0]; 1 occurrence(s). See issues.json for evidence.
- **E0222 floor_collision_visual_mismatch** (candidate), route:upper_hall at [36.0, -5.0441, -25.3636]; 1 occurrence(s). See issues.json for evidence.
- **E0223 floor_collision_visual_mismatch** (candidate), route:upper_hall at [36.0, -5.0441, -25.8182]; 1 occurrence(s). See issues.json for evidence.
- **E0225 floor_collision_visual_mismatch** (candidate), route:upper_hall at [36.0, -6.032, -26.7273]; 2 occurrence(s). See issues.json for evidence.
- **E0226 floor_collision_visual_mismatch** (candidate), route:upper_hall at [37.848, -5.9917, -26.7273]; 1 occurrence(s). See issues.json for evidence.
- **E0227 floor_collision_visual_mismatch** (candidate), route:upper_hall at [36.0, -6.032, -28.0909]; 1 occurrence(s). See issues.json for evidence.
- **E0228 floor_collision_visual_mismatch** (candidate), route:first_stair at [32.3571, -8.6194, -41.096]; 1 occurrence(s). See issues.json for evidence.
- **E0229 floor_collision_visual_mismatch** (candidate), route:central_ledge at [8.8333, -17.551, 16.1111]; 1 occurrence(s). See issues.json for evidence.
- **E0233 floor_collision_visual_mismatch** (candidate), route:nave at [-27.0909, -19.9858, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0234 floor_collision_visual_mismatch** (candidate), route:second_stair at [-33.5385, -22.111, 34.404]; 1 occurrence(s). See issues.json for evidence.
- **E0235 floor_collision_visual_mismatch** (candidate), route:second_stair at [-32.404, -22.777, 28.8571]; 1 occurrence(s). See issues.json for evidence.
- **E0272 floor_collision_visual_mismatch** (candidate), route:return_stair at [42.23, -18.9764, 13.2623]; 1 occurrence(s). See issues.json for evidence.
- **E0274 floor_collision_visual_mismatch** (candidate), route:return_gallery at [27.3308, -10.3486, 11.68]; 2 occurrence(s). See issues.json for evidence.
- **E0280 floor_collision_visual_mismatch** (candidate), route:return_gallery at [23.5427, -10.48, 8.4131]; 1 occurrence(s). See issues.json for evidence.
- **E0281 floor_collision_visual_mismatch** (candidate), route:return_gallery at [20.32, -11.0, -28.0]; 1 occurrence(s). See issues.json for evidence.
- **E0286 missing_floor_candidate** (candidate), route:cave_bypass at [-47.5, -23.0, 3.5]; 1 occurrence(s). See issues.json for evidence.
- **E0287 missing_floor_candidate** (candidate), route:cave_bypass at [-47.0, -23.0, 1.5]; 1 occurrence(s). See issues.json for evidence.
- **E0288 missing_floor_candidate** (candidate), route:cave_bypass at [-46.5, -23.0, -0.5]; 1 occurrence(s). See issues.json for evidence.
- **E0289 missing_floor_candidate** (candidate), room:entry at [-46.0, 0.0, -18.0]; 1 occurrence(s). See issues.json for evidence.
- **E0290 missing_floor_candidate** (candidate), route:cave_bypass at [-46.0, -23.0, -3.0]; 2 occurrence(s). See issues.json for evidence.
- **E0291 missing_floor_candidate** (candidate), route:cave_bypass at [-46.0, -23.0, -2.0]; 1 occurrence(s). See issues.json for evidence.
- **E0292 missing_floor_candidate** (candidate), route:cave_bypass at [-45.5, -23.0, -5.0]; 2 occurrence(s). See issues.json for evidence.
- **E0293 missing_floor_candidate** (candidate), route:cave_bypass at [-45.5, -23.0, -4.0]; 1 occurrence(s). See issues.json for evidence.
- **E0294 missing_floor_candidate** (candidate), room:entry at [-45.0, 0.0, -17.5]; 1 occurrence(s). See issues.json for evidence.
- **E0295 missing_floor_candidate** (candidate), route:cave_bypass at [-45.0, -23.0, -7.0]; 4 occurrence(s). See issues.json for evidence.
- **E0296 missing_floor_candidate** (candidate), route:cave_bypass at [-45.0, -23.0, -6.0]; 2 occurrence(s). See issues.json for evidence.
- **E0297 missing_floor_candidate** (candidate), room:entry at [-44.0, 0.0, -17.0]; 1 occurrence(s). See issues.json for evidence.
- **E0298 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 14.5]; 2 occurrence(s). See issues.json for evidence.
- **E0299 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 15.5]; 2 occurrence(s). See issues.json for evidence.
- **E0300 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 16.5]; 2 occurrence(s). See issues.json for evidence.
- **E0301 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 17.5]; 2 occurrence(s). See issues.json for evidence.
- **E0302 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 18.5]; 2 occurrence(s). See issues.json for evidence.
- **E0303 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 19.5]; 2 occurrence(s). See issues.json for evidence.
- **E0304 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 20.5]; 2 occurrence(s). See issues.json for evidence.
- **E0305 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 21.5]; 2 occurrence(s). See issues.json for evidence.
- **E0306 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 22.5]; 2 occurrence(s). See issues.json for evidence.
- **E0307 missing_floor_candidate** (candidate), route:root_tunnel at [-43.5, -23.0, 23.5]; 3 occurrence(s). See issues.json for evidence.
- **E0308 missing_floor_candidate** (candidate), room:entry at [-43.0, 0.0, -16.5]; 1 occurrence(s). See issues.json for evidence.
- **E0309 missing_floor_candidate** (candidate), route:cave_bypass at [-43.0, -23.0, 3.5]; 2 occurrence(s). See issues.json for evidence.
- **E0310 missing_floor_candidate** (candidate), route:cave_bypass at [-42.5, -23.0, 1.0]; 1 occurrence(s). See issues.json for evidence.
- **E0311 missing_floor_candidate** (candidate), route:cave_bypass at [-42.5, -23.0, 1.5]; 1 occurrence(s). See issues.json for evidence.
- **E0312 missing_floor_candidate** (candidate), room:ossuary at [-42.0, -10.0, -28.0]; 2 occurrence(s). See issues.json for evidence.
- **E0313 missing_floor_candidate** (candidate), room:entry at [-42.0, 0.0, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0314 missing_floor_candidate** (candidate), route:cave_bypass at [-42.0, -23.0, -8.0]; 4 occurrence(s). See issues.json for evidence.
- **E0315 missing_floor_candidate** (candidate), route:cave_bypass at [-42.0, -23.0, -1.5]; 2 occurrence(s). See issues.json for evidence.
- **E0316 missing_floor_candidate** (candidate), route:cave_bypass at [-42.0, -23.0, -1.0]; 2 occurrence(s). See issues.json for evidence.
- **E0317 missing_floor_candidate** (candidate), room:ossuary at [-41.0, -10.0, -27.0]; 2 occurrence(s). See issues.json for evidence.
- **E0318 missing_floor_candidate** (candidate), room:entry at [-41.0, 0.0, -15.5]; 1 occurrence(s). See issues.json for evidence.
- **E0319 missing_floor_candidate** (candidate), room:bones at [-41.0, -10.0, -12.5]; 1 occurrence(s). See issues.json for evidence.
- **E0320 missing_floor_candidate** (candidate), route:cave_bypass at [-41.0, -23.0, -7.0]; 2 occurrence(s). See issues.json for evidence.
- **E0321 missing_floor_candidate** (candidate), route:root_tunnel at [-41.0, -23.0, 26.5]; 3 occurrence(s). See issues.json for evidence.
- **E0322 missing_floor_candidate** (candidate), room:bones at [-40.5, -10.0, -12.0]; 1 occurrence(s). See issues.json for evidence.
- **E0323 missing_floor_candidate** (candidate), room:ossuary at [-40.0, -10.0, -26.0]; 2 occurrence(s). See issues.json for evidence.
- **E0324 missing_floor_candidate** (candidate), room:entry at [-40.0, 0.0, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0325 missing_floor_candidate** (candidate), room:bones at [-40.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0326 missing_floor_candidate** (candidate), route:root_tunnel at [-40.0, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0327 missing_floor_candidate** (candidate), route:cave_bypass at [-39.5, -23.0, -6.0]; 1 occurrence(s). See issues.json for evidence.
- **E0328 missing_floor_candidate** (candidate), room:ossuary at [-39.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0329 missing_floor_candidate** (candidate), room:entry at [-39.0, 0.0, -15.5]; 1 occurrence(s). See issues.json for evidence.
- **E0330 missing_floor_candidate** (candidate), room:bones at [-39.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0331 missing_floor_candidate** (candidate), route:root_tunnel at [-39.0, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0332 missing_floor_candidate** (candidate), room:ossuary at [-38.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0333 missing_floor_candidate** (candidate), room:entry at [-38.0, 0.0, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0334 missing_floor_candidate** (candidate), room:bones at [-38.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0335 missing_floor_candidate** (candidate), route:root_tunnel at [-38.0, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0336 missing_floor_candidate** (candidate), room:ossuary at [-37.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0337 missing_floor_candidate** (candidate), room:entry at [-37.0, 0.0, -16.5]; 1 occurrence(s). See issues.json for evidence.
- **E0338 missing_floor_candidate** (candidate), room:bones at [-37.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0339 missing_floor_candidate** (candidate), route:root_tunnel at [-37.0, -23.0, 26.0]; 3 occurrence(s). See issues.json for evidence.
- **E0340 missing_floor_candidate** (candidate), route:root_tunnel at [-37.0, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0341 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 20.5]; 2 occurrence(s). See issues.json for evidence.
- **E0342 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 25.5]; 2 occurrence(s). See issues.json for evidence.
- **E0343 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 26.5]; 2 occurrence(s). See issues.json for evidence.
- **E0344 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 27.5]; 2 occurrence(s). See issues.json for evidence.
- **E0345 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 28.5]; 2 occurrence(s). See issues.json for evidence.
- **E0346 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 29.5]; 2 occurrence(s). See issues.json for evidence.
- **E0347 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 30.5]; 2 occurrence(s). See issues.json for evidence.
- **E0348 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 31.5]; 2 occurrence(s). See issues.json for evidence.
- **E0349 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 32.5]; 2 occurrence(s). See issues.json for evidence.
- **E0350 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 33.5]; 2 occurrence(s). See issues.json for evidence.
- **E0351 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 34.5]; 2 occurrence(s). See issues.json for evidence.
- **E0352 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 35.5]; 2 occurrence(s). See issues.json for evidence.
- **E0353 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 36.5]; 2 occurrence(s). See issues.json for evidence.
- **E0354 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 37.5]; 2 occurrence(s). See issues.json for evidence.
- **E0355 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.5, -23.0, 38.5]; 1 occurrence(s). See issues.json for evidence.
- **E0356 missing_floor_candidate** (candidate), room:entry at [-36.0, 0.0, -17.0]; 1 occurrence(s). See issues.json for evidence.
- **E0357 missing_floor_candidate** (candidate), room:bones at [-36.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0358 missing_floor_candidate** (candidate), room:second_stair_hall at [-36.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0359 missing_floor_candidate** (candidate), room:entry at [-35.0, 0.0, -17.5]; 1 occurrence(s). See issues.json for evidence.
- **E0360 missing_floor_candidate** (candidate), room:bones at [-35.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0361 missing_floor_candidate** (candidate), room:second_stair_hall at [-35.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0362 missing_floor_candidate** (candidate), room:ossuary at [-34.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0363 missing_floor_candidate** (candidate), route:ossuary_loop at [-34.0, -10.0, -25.0]; 4 occurrence(s). See issues.json for evidence.
- **E0364 missing_floor_candidate** (candidate), room:entry at [-34.0, 0.0, -18.0]; 1 occurrence(s). See issues.json for evidence.
- **E0365 missing_floor_candidate** (candidate), room:bones at [-34.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0366 missing_floor_candidate** (candidate), room:second_stair_hall at [-34.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0367 missing_floor_candidate** (candidate), room:entry at [-33.5, 0.0, -19.5]; 1 occurrence(s). See issues.json for evidence.
- **E0368 missing_floor_candidate** (candidate), room:ossuary at [-33.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0369 missing_floor_candidate** (candidate), route:ossuary_loop at [-33.0, -10.0, -25.0]; 4 occurrence(s). See issues.json for evidence.
- **E0370 missing_floor_candidate** (candidate), room:entry at [-33.0, 0.0, -21.0]; 1 occurrence(s). See issues.json for evidence.
- **E0371 missing_floor_candidate** (candidate), route:entry at [-33.0, 0.0, -21.0]; 1 occurrence(s). See issues.json for evidence.
- **E0372 missing_floor_candidate** (candidate), room:bones at [-33.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0373 missing_floor_candidate** (candidate), room:second_stair_hall at [-33.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0374 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.5, -10.0, -20.5]; 1 occurrence(s). See issues.json for evidence.
- **E0375 missing_floor_candidate** (candidate), room:ossuary at [-32.0, -10.0, -25.0]; 2 occurrence(s). See issues.json for evidence.
- **E0376 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -25.0]; 3 occurrence(s). See issues.json for evidence.
- **E0377 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -24.0]; 2 occurrence(s). See issues.json for evidence.
- **E0378 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -23.0]; 2 occurrence(s). See issues.json for evidence.
- **E0379 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -22.0]; 2 occurrence(s). See issues.json for evidence.
- **E0380 missing_floor_candidate** (candidate), route:ossuary_loop at [-32.0, -10.0, -21.0]; 2 occurrence(s). See issues.json for evidence.
- **E0381 missing_floor_candidate** (candidate), room:bones at [-32.0, -10.0, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0382 missing_floor_candidate** (candidate), route:nave at [-32.0, -20.0, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0383 missing_floor_candidate** (candidate), route:nave at [-32.0, -20.0, 24.5]; 2 occurrence(s). See issues.json for evidence.
- **E0384 missing_floor_candidate** (candidate), room:second_stair_hall at [-32.0, -23.0, 38.5]; 2 occurrence(s). See issues.json for evidence.
- **E0385 missing_floor_candidate** (candidate), route:nave at [-31.5, -20.0, 22.5]; 1 occurrence(s). See issues.json for evidence.
- **E0004 surface_backface_candidate** (candidate), room:entry at [-46.65, 4.88, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0006 surface_backface_candidate** (candidate), room:entry at [-46.65, 4.88, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0007 surface_backface_candidate** (candidate), room:entry at [-44.65, 4.88, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0009 surface_backface_candidate** (candidate), room:entry at [-42.65, 4.88, -31.65]; 1 occurrence(s). See issues.json for evidence.
- **E0011 surface_backface_candidate** (candidate), room:entry at [-40.65, 4.88, -31.65]; 1 occurrence(s). See issues.json for evidence.
- **E0014 surface_backface_candidate** (candidate), room:entry at [-36.65, 4.88, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0015 surface_backface_candidate** (candidate), room:entry at [-33.65, 4.88, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0017 surface_backface_candidate** (candidate), room:entry at [-32.65, 4.88, -28.65]; 1 occurrence(s). See issues.json for evidence.
- **E0018 surface_backface_candidate** (candidate), room:entry at [-31.65, 4.88, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0021 surface_backface_candidate** (candidate), room:antechamber at [-26.65, 6.88, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0023 surface_backface_candidate** (candidate), room:antechamber at [-24.65, 5.5388, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0024 surface_backface_candidate** (candidate), room:antechamber at [-23.65, 0.9686, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0025 surface_backface_candidate** (candidate), room:antechamber at [-23.65, 4.8425, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0030 surface_backface_candidate** (candidate), room:antechamber at [-17.65, 6.88, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0031 surface_backface_candidate** (candidate), room:antechamber at [-16.65, 6.88, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0035 surface_backface_candidate** (candidate), room:restraint at [26.35, -0.0891, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0038 surface_backface_candidate** (candidate), room:restraint at [26.35, -1.4118, -6.65]; 1 occurrence(s). See issues.json for evidence.
- **E0039 surface_backface_candidate** (candidate), room:restraint at [27.35, 9.88, -3.65]; 1 occurrence(s). See issues.json for evidence.
- **E0040 surface_backface_candidate** (candidate), room:restraint at [28.35, 9.88, -2.65]; 1 occurrence(s). See issues.json for evidence.
- **E0042 surface_backface_candidate** (candidate), room:restraint at [30.35, 4.8444, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0045 surface_backface_candidate** (candidate), room:restraint at [33.35, -2.4906, -22.65]; 2 occurrence(s). See issues.json for evidence.
- **E0047 surface_backface_candidate** (candidate), room:restraint at [40.35, 9.88, -21.65]; 1 occurrence(s). See issues.json for evidence.
- **E0049 surface_backface_candidate** (candidate), room:restraint at [41.35, 9.88, -20.65]; 1 occurrence(s). See issues.json for evidence.
- **E0052 surface_backface_candidate** (candidate), room:cells at [30.35, -3.459, 3.35]; 1 occurrence(s). See issues.json for evidence.
- **E0056 surface_backface_candidate** (candidate), room:cells at [31.35, 0.88, 11.35]; 1 occurrence(s). See issues.json for evidence.
- **E0057 surface_backface_candidate** (candidate), room:cells at [36.35, -2.497, 0.35]; 2 occurrence(s). See issues.json for evidence.
- **E0061 surface_backface_candidate** (candidate), room:cells at [41.35, 0.88, 1.35]; 1 occurrence(s). See issues.json for evidence.
- **E0064 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.5357, -33.65]; 1 occurrence(s). See issues.json for evidence.
- **E0065 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.1592, -33.65]; 1 occurrence(s). See issues.json for evidence.
- **E0067 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.5416, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0068 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.1629, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0069 surface_backface_candidate** (candidate), room:chapel at [-10.65, 5.88, -24.65]; 1 occurrence(s). See issues.json for evidence.
- **E0074 surface_backface_candidate** (candidate), room:chapel at [0.35, -1.371, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0076 surface_backface_candidate** (candidate), room:chapel at [1.35, -7.083, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0078 surface_backface_candidate** (candidate), room:chapel at [5.35, -8.5338, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0079 surface_backface_candidate** (candidate), room:chapel at [5.35, -1.7632, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0082 surface_backface_candidate** (candidate), room:chapel at [9.35, 1.369, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0085 surface_backface_candidate** (candidate), room:chapel at [11.35, -4.753, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0087 surface_backface_candidate** (candidate), room:chapel at [12.35, -7.6228, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0089 surface_backface_candidate** (candidate), room:chapel at [16.35, -10.12, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0090 surface_backface_candidate** (candidate), room:chapel at [16.35, 5.88, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0092 surface_backface_candidate** (candidate), room:chapel at [17.35, 5.88, -40.65]; 1 occurrence(s). See issues.json for evidence.
- **E0095 surface_backface_candidate** (candidate), room:nave at [-13.65, -15.4908, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0097 surface_backface_candidate** (candidate), room:nave at [-13.65, -11.6142, 30.35]; 1 occurrence(s). See issues.json for evidence.
- **E0099 surface_backface_candidate** (candidate), room:nave at [-13.65, -11.1106, 32.35]; 1 occurrence(s). See issues.json for evidence.
- **E0100 surface_backface_candidate** (candidate), room:nave at [-13.65, -17.0418, 33.35]; 1 occurrence(s). See issues.json for evidence.
- **E0102 surface_backface_candidate** (candidate), room:nave at [-13.65, -3.4791, 34.35]; 1 occurrence(s). See issues.json for evidence.
- **E0104 surface_backface_candidate** (candidate), room:nave at [-13.65, -12.5095, 35.35]; 1 occurrence(s). See issues.json for evidence.
- **E0107 surface_backface_candidate** (candidate), room:nave at [-13.65, -8.6723, 37.35]; 1 occurrence(s). See issues.json for evidence.
- **E0109 surface_backface_candidate** (candidate), room:nave at [-13.65, -10.7173, 38.35]; 1 occurrence(s). See issues.json for evidence.
- **E0113 surface_backface_candidate** (candidate), room:nave at [-13.65, -14.1826, 42.35]; 1 occurrence(s). See issues.json for evidence.
- **E0115 surface_backface_candidate** (candidate), room:nave at [-13.65, -13.204, 43.35]; 1 occurrence(s). See issues.json for evidence.
- **E0117 surface_backface_candidate** (candidate), room:nave at [-13.65, -14.5481, 44.35]; 1 occurrence(s). See issues.json for evidence.
- **E0118 surface_backface_candidate** (candidate), room:nave at [-12.65, 1.88, 47.35]; 1 occurrence(s). See issues.json for evidence.
- **E0119 surface_backface_candidate** (candidate), room:nave at [-11.65, 1.88, 48.35]; 1 occurrence(s). See issues.json for evidence.
- **E0122 surface_backface_candidate** (candidate), room:nave at [-5.65, -13.1914, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0123 surface_backface_candidate** (candidate), room:nave at [-4.65, -17.6634, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0124 surface_backface_candidate** (candidate), room:nave at [-3.65, -16.7567, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0125 surface_backface_candidate** (candidate), room:nave at [-3.65, -13.1603, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0128 surface_backface_candidate** (candidate), room:nave at [0.35, -11.5977, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0130 surface_backface_candidate** (candidate), room:nave at [3.35, -16.2503, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0132 surface_backface_candidate** (candidate), room:nave at [9.35, -16.4982, 28.35]; 2 occurrence(s). See issues.json for evidence.
- **E0133 surface_backface_candidate** (candidate), room:nave at [12.35, -18.12, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0134 surface_backface_candidate** (candidate), room:nave at [12.35, 1.88, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0135 surface_backface_candidate** (candidate), room:nave at [13.35, 1.88, 30.35]; 1 occurrence(s). See issues.json for evidence.
- **E0142 surface_backface_candidate** (candidate), room:ossuary at [-41.65, -3.9098, -31.65]; 1 occurrence(s). See issues.json for evidence.
- **E0144 surface_backface_candidate** (candidate), room:ossuary at [-41.65, -5.8431, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0146 surface_backface_candidate** (candidate), room:ossuary at [-40.65, -10.12, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0147 surface_backface_candidate** (candidate), room:ossuary at [-40.65, -3.12, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0148 surface_backface_candidate** (candidate), room:ossuary at [-39.65, -10.12, -25.65]; 1 occurrence(s). See issues.json for evidence.
- **E0149 surface_backface_candidate** (candidate), room:ossuary at [-39.65, -3.12, -25.65]; 1 occurrence(s). See issues.json for evidence.
- **E0151 surface_backface_candidate** (candidate), room:ossuary at [-36.65, -7.9172, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0152 surface_backface_candidate** (candidate), room:ossuary at [-35.65, -9.4784, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0155 surface_backface_candidate** (candidate), room:ossuary at [-31.65, -9.74, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0158 surface_backface_candidate** (candidate), room:ossuary at [-27.65, -5.2674, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0160 surface_backface_candidate** (candidate), room:ossuary at [-26.65, -4.6, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0162 surface_backface_candidate** (candidate), room:ossuary at [-23.65, -10.12, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0163 surface_backface_candidate** (candidate), room:ossuary at [-23.65, -3.12, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0164 surface_backface_candidate** (candidate), room:ossuary at [-22.65, -3.12, -40.65]; 1 occurrence(s). See issues.json for evidence.
- **E0169 surface_backface_candidate** (candidate), room:bones at [-31.65, -8.4224, -19.65]; 2 occurrence(s). See issues.json for evidence.
- **E0172 surface_backface_candidate** (candidate), room:bones at [-29.65, -6.8438, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0179 surface_backface_candidate** (candidate), room:bones at [-23.65, -8.224, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0181 surface_backface_candidate** (candidate), room:bones at [-22.65, -6.8699, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0182 surface_backface_candidate** (candidate), room:window at [-27.15, -9.011, -9.65]; 1 occurrence(s). See issues.json for evidence.
- **E0186 surface_backface_candidate** (candidate), room:bell at [26.35, -16.4777, 33.35]; 2 occurrence(s). See issues.json for evidence.
- **E0187 surface_backface_candidate** (candidate), room:bell at [26.35, -16.4933, 38.35]; 2 occurrence(s). See issues.json for evidence.
- **E0188 surface_backface_candidate** (candidate), room:bell at [26.35, -14.1597, 39.35]; 1 occurrence(s). See issues.json for evidence.
- **E0189 surface_backface_candidate** (candidate), room:bell at [26.35, -16.4872, 41.35]; 2 occurrence(s). See issues.json for evidence.
- **E0190 surface_backface_candidate** (candidate), room:bell at [26.35, -16.4899, 46.35]; 2 occurrence(s). See issues.json for evidence.
- **E0191 surface_backface_candidate** (candidate), room:bell at [37.35, -10.5244, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0192 surface_backface_candidate** (candidate), room:bell at [39.35, -15.0159, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0193 surface_backface_candidate** (candidate), room:bell at [40.35, -12.4262, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0194 surface_backface_candidate** (candidate), room:bell at [44.35, -6.12, 30.35]; 1 occurrence(s). See issues.json for evidence.
- **E0195 surface_backface_candidate** (candidate), room:bell at [45.35, -6.12, 31.35]; 1 occurrence(s). See issues.json for evidence.
- **E0196 surface_backface_candidate** (candidate), room:choir at [26.35, -26.6173, -8.65]; 1 occurrence(s). See issues.json for evidence.
- **E0197 surface_backface_candidate** (candidate), room:choir at [26.35, -26.3869, -8.65]; 1 occurrence(s). See issues.json for evidence.
- **E0198 surface_backface_candidate** (candidate), room:choir at [26.35, -25.7403, -2.65]; 1 occurrence(s). See issues.json for evidence.
- **E0199 surface_backface_candidate** (candidate), room:choir at [26.35, -19.2787, -1.65]; 1 occurrence(s). See issues.json for evidence.
- **E0200 surface_backface_candidate** (candidate), room:choir at [26.35, -26.6115, -0.65]; 1 occurrence(s). See issues.json for evidence.
- **E0201 surface_backface_candidate** (candidate), room:choir at [26.35, -10.8882, -0.65]; 1 occurrence(s). See issues.json for evidence.
- **E0203 visible_ceiling_gap** (candidate), route:entry at [-19.9, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0204 visible_ceiling_gap** (candidate), route:entry at [-22.0, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0220 visible_ceiling_gap** (candidate), route:upper_hall at [24.0, -2.4, -10.0]; 2 occurrence(s). See issues.json for evidence.
- **E0221 visible_ceiling_gap** (candidate), route:upper_hall at [24.9524, -2.4, -9.8571]; 2 occurrence(s). See issues.json for evidence.
- **E0230 visible_ceiling_gap** (candidate), route:nave at [7.0, -16.4, 21.0]; 1 occurrence(s). See issues.json for evidence.
- **E0271 visible_ceiling_gap** (candidate), route:choir at [25.4706, -26.4, 5.9412]; 1 occurrence(s). See issues.json for evidence.
- **E0282 visible_ceiling_gap** (candidate), route:ossuary_loop at [-15.5, -8.4, -31.68]; 1 occurrence(s). See issues.json for evidence.
- **E0283 visible_ceiling_gap** (candidate), route:ossuary_loop at [-18.0, -8.4, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0284 visible_ceiling_gap** (candidate), route:ossuary_loop at [-20.0, -8.4, -34.32]; 1 occurrence(s). See issues.json for evidence.
- **E0285 visible_ceiling_gap** (candidate), route:ossuary_loop at [-15.0, -8.4, -37.68]; 1 occurrence(s). See issues.json for evidence.
- **E0202 visible_floor_gap** (candidate), route:entry at [-19.9, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0205 visible_floor_gap** (candidate), route:high_span at [-18.1905, 1.3333, -15.2381]; 1 occurrence(s). See issues.json for evidence.
- **E0206 visible_floor_gap** (candidate), route:high_span at [-16.2857, 1.2, -14.8571]; 2 occurrence(s). See issues.json for evidence.
- **E0207 visible_floor_gap** (candidate), route:high_span at [-14.381, 1.0667, -14.4762]; 1 occurrence(s). See issues.json for evidence.
- **E0208 visible_floor_gap** (candidate), route:high_span at [-12.0, 0.9, -14.0]; 2 occurrence(s). See issues.json for evidence.
- **E0209 visible_floor_gap** (candidate), route:high_span at [-6.7895, 0.4947, -12.8421]; 1 occurrence(s). See issues.json for evidence.
- **E0210 visible_floor_gap** (candidate), route:high_span at [-5.3684, 0.3842, -12.5263]; 1 occurrence(s). See issues.json for evidence.
- **E0211 visible_floor_gap** (candidate), route:high_span at [-3.0, 0.2, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0212 visible_floor_gap** (candidate), route:high_span at [0.0, -0.1, -13.5]; 1 occurrence(s). See issues.json for evidence.
- **E0213 visible_floor_gap** (candidate), route:high_span at [3.0, -0.4, -15.0]; 2 occurrence(s). See issues.json for evidence.
- **E0214 visible_floor_gap** (candidate), route:high_span at [5.4, -0.6, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0215 visible_floor_gap** (candidate), route:high_span at [7.8, -0.8, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0216 visible_floor_gap** (candidate), route:high_span at [10.2, -1.0, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0217 visible_floor_gap** (candidate), route:high_span at [12.6, -1.2, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0218 visible_floor_gap** (candidate), route:high_span at [14.52, -1.36, -15.0]; 3 occurrence(s). See issues.json for evidence.
- **E0219 visible_floor_gap** (candidate), route:high_span at [18.4286, -1.781, -13.0952]; 1 occurrence(s). See issues.json for evidence.
- **E0224 visible_floor_gap** (candidate), route:upper_hall at [37.848, -3.3091, -26.2727]; 1 occurrence(s). See issues.json for evidence.
- **E0231 visible_floor_gap** (candidate), route:nave at [-26.1212, -18.1576, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0232 visible_floor_gap** (candidate), route:nave at [-26.6061, -18.1879, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0236 visible_floor_gap** (candidate), route:low_span at [-20.6316, -21.6632, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0237 visible_floor_gap** (candidate), route:low_span at [-19.6842, -21.7684, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0238 visible_floor_gap** (candidate), route:low_span at [-17.3158, -22.0316, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0239 visible_floor_gap** (candidate), route:low_span at [-16.3684, -22.1368, -16.0]; 2 occurrence(s). See issues.json for evidence.
- **E0240 visible_floor_gap** (candidate), route:low_span at [-14.9474, -22.2947, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0241 visible_floor_gap** (candidate), route:low_span at [-14.0, -22.4, -16.0]; 2 occurrence(s). See issues.json for evidence.
- **E0242 visible_floor_gap** (candidate), route:low_span at [-11.1053, -22.6895, -11.3684]; 1 occurrence(s). See issues.json for evidence.
- **E0243 visible_floor_gap** (candidate), route:low_span at [-9.7895, -22.8211, -9.2632]; 1 occurrence(s). See issues.json for evidence.
- **E0244 visible_floor_gap** (candidate), route:low_span at [-9.0, -22.9, -8.0]; 2 occurrence(s). See issues.json for evidence.
- **E0245 visible_floor_gap** (candidate), route:low_span at [-8.3333, -22.9556, -6.6667]; 1 occurrence(s). See issues.json for evidence.
- **E0246 visible_floor_gap** (candidate), route:low_span at [-7.6667, -23.0111, -5.3333]; 1 occurrence(s). See issues.json for evidence.
- **E0247 visible_floor_gap** (candidate), route:low_span at [-7.0, -23.0667, -4.0]; 1 occurrence(s). See issues.json for evidence.
- **E0248 visible_floor_gap** (candidate), route:low_span at [-6.3333, -23.1222, -2.6667]; 1 occurrence(s). See issues.json for evidence.
- **E0249 visible_floor_gap** (candidate), route:low_span at [-5.6667, -23.1778, -1.3333]; 1 occurrence(s). See issues.json for evidence.
- **E0250 visible_floor_gap** (candidate), route:low_span at [-5.4444, -23.1963, -0.8889]; 1 occurrence(s). See issues.json for evidence.
- **E0251 visible_floor_gap** (candidate), route:low_span at [-5.0, -23.2333, 0.0]; 1 occurrence(s). See issues.json for evidence.
- **E0252 visible_floor_gap** (candidate), route:low_span at [-4.3333, -23.2889, 1.3333]; 1 occurrence(s). See issues.json for evidence.
- **E0253 visible_floor_gap** (candidate), route:low_span at [-3.6667, -23.3444, 2.6667]; 1 occurrence(s). See issues.json for evidence.
- **E0254 visible_floor_gap** (candidate), route:low_span at [-3.0, -23.4, 4.0]; 2 occurrence(s). See issues.json for evidence.
- **E0255 visible_floor_gap** (candidate), route:low_span at [-1.7368, -23.5579, 4.7895]; 1 occurrence(s). See issues.json for evidence.
- **E0256 visible_floor_gap** (candidate), route:low_span at [0.3684, -23.8211, 6.1053]; 1 occurrence(s). See issues.json for evidence.
- **E0257 visible_floor_gap** (candidate), route:low_span at [1.6316, -23.9789, 6.8947]; 1 occurrence(s). See issues.json for evidence.
- **E0258 visible_floor_gap** (candidate), route:low_span at [5.0, -24.4, 9.0]; 2 occurrence(s). See issues.json for evidence.
- **E0259 visible_floor_gap** (candidate), route:low_span at [4.7862, -24.4, 7.5032]; 1 occurrence(s). See issues.json for evidence.
- **E0260 visible_floor_gap** (candidate), route:low_span at [7.3333, -24.7333, 8.6667]; 1 occurrence(s). See issues.json for evidence.
- **E0261 visible_floor_gap** (candidate), route:low_span at [8.2667, -24.8667, 8.5333]; 1 occurrence(s). See issues.json for evidence.
- **E0262 visible_floor_gap** (candidate), route:low_span at [9.6667, -25.0667, 8.3333]; 2 occurrence(s). See issues.json for evidence.
- **E0263 visible_floor_gap** (candidate), route:low_span at [12.0, -25.4, 8.0]; 2 occurrence(s). See issues.json for evidence.
- **E0264 visible_floor_gap** (candidate), route:low_span at [13.5385, -25.5154, 6.0769]; 1 occurrence(s). See issues.json for evidence.
- **E0265 visible_floor_gap** (candidate), route:low_span at [14.4615, -25.5846, 4.9231]; 1 occurrence(s). See issues.json for evidence.
- **E0266 visible_floor_gap** (candidate), route:low_span at [16.0, -25.7, 3.0]; 2 occurrence(s). See issues.json for evidence.
- **E0267 visible_floor_gap** (candidate), route:low_span at [15.9719, -25.735, 4.5844]; 1 occurrence(s). See issues.json for evidence.
- **E0268 visible_floor_gap** (candidate), route:low_span at [17.8, -25.84, 3.6]; 2 occurrence(s). See issues.json for evidence.
- **E0269 visible_floor_gap** (candidate), route:low_span at [20.5, -26.05, 4.5]; 1 occurrence(s). See issues.json for evidence.
- **E0270 visible_floor_gap** (candidate), route:low_span at [22.75, -26.225, 5.25]; 1 occurrence(s). See issues.json for evidence.
- **E0273 visible_floor_gap** (candidate), route:return_gallery at [28.3, -8.4, 8.32]; 2 occurrence(s). See issues.json for evidence.
- **E0275 visible_floor_gap** (candidate), route:return_gallery at [27.3308, -8.4, 8.32]; 2 occurrence(s). See issues.json for evidence.
- **E0276 visible_floor_gap** (candidate), route:return_gallery at [26.3615, -8.4, 11.68]; 1 occurrence(s). See issues.json for evidence.
- **E0277 visible_floor_gap** (candidate), route:return_gallery at [26.3615, -8.4, 10.0]; 1 occurrence(s). See issues.json for evidence.
- **E0278 visible_floor_gap** (candidate), route:return_gallery at [26.3615, -8.4, 8.32]; 1 occurrence(s). See issues.json for evidence.
- **E0279 visible_floor_gap** (candidate), route:return_gallery at [22.9692, -8.4, 11.68]; 1 occurrence(s). See issues.json for evidence.
- **E0002 raised_render_surface** (candidate), room:entry at [-47.65, 0.2764, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0003 raised_render_surface** (candidate), room:entry at [-47.65, 0.2763, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0005 raised_render_surface** (candidate), room:entry at [-46.65, 0.2821, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0008 raised_render_surface** (candidate), room:entry at [-44.65, 0.2817, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0010 raised_render_surface** (candidate), room:entry at [-42.65, 0.2842, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0012 raised_render_surface** (candidate), room:entry at [-40.65, 0.2793, -15.65]; 1 occurrence(s). See issues.json for evidence.
- **E0013 raised_render_surface** (candidate), room:entry at [-37.65, 0.2858, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0016 raised_render_surface** (candidate), room:entry at [-33.65, 0.2799, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0019 raised_render_surface** (candidate), room:antechamber at [-27.65, 0.2831, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0020 raised_render_surface** (candidate), room:antechamber at [-27.65, 0.28, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0022 raised_render_surface** (candidate), room:antechamber at [-24.65, 0.281, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0026 raised_render_surface** (candidate), room:antechamber at [-22.65, 0.2912, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0027 raised_render_surface** (candidate), room:antechamber at [-21.65, 0.2895, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0028 raised_render_surface** (candidate), room:antechamber at [-20.65, 0.2833, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0029 raised_render_surface** (candidate), room:antechamber at [-19.65, 0.282, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0032 raised_render_surface** (candidate), room:antechamber at [-16.65, 0.2905, -18.65]; 1 occurrence(s). See issues.json for evidence.
- **E0033 raised_render_surface** (candidate), room:restraint at [26.35, -3.7188, -17.65]; 1 occurrence(s). See issues.json for evidence.
- **E0034 raised_render_surface** (candidate), room:restraint at [26.35, -3.7195, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0036 raised_render_surface** (candidate), room:restraint at [26.35, -3.7149, -12.65]; 1 occurrence(s). See issues.json for evidence.
- **E0037 raised_render_surface** (candidate), room:restraint at [26.35, -3.7158, -6.65]; 1 occurrence(s). See issues.json for evidence.
- **E0041 raised_render_surface** (candidate), room:restraint at [30.35, -3.712, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0043 raised_render_surface** (candidate), room:restraint at [31.35, -3.7122, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0044 raised_render_surface** (candidate), room:restraint at [32.35, -3.7169, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0046 raised_render_surface** (candidate), room:restraint at [39.35, -3.7148, -2.65]; 1 occurrence(s). See issues.json for evidence.
- **E0048 raised_render_surface** (candidate), room:restraint at [40.35, -3.7183, -3.65]; 1 occurrence(s). See issues.json for evidence.
- **E0050 raised_render_surface** (candidate), room:restraint at [41.35, -3.8274, -4.65]; 1 occurrence(s). See issues.json for evidence.
- **E0051 raised_render_surface** (candidate), room:cells at [30.35, -3.7167, 2.35]; 1 occurrence(s). See issues.json for evidence.
- **E0053 raised_render_surface** (candidate), room:cells at [30.35, -3.721, 4.35]; 1 occurrence(s). See issues.json for evidence.
- **E0054 raised_render_surface** (candidate), room:cells at [30.35, -3.7135, 5.35]; 1 occurrence(s). See issues.json for evidence.
- **E0055 raised_render_surface** (candidate), room:cells at [30.35, -3.7197, 6.35]; 1 occurrence(s). See issues.json for evidence.
- **E0058 raised_render_surface** (candidate), room:cells at [37.35, -3.7107, 0.35]; 1 occurrence(s). See issues.json for evidence.
- **E0059 raised_render_surface** (candidate), room:cells at [38.35, -3.7193, 0.35]; 1 occurrence(s). See issues.json for evidence.
- **E0060 raised_render_surface** (candidate), room:cells at [40.35, -3.7168, 11.35]; 1 occurrence(s). See issues.json for evidence.
- **E0062 raised_render_surface** (candidate), room:cells at [41.35, -3.7227, 10.35]; 1 occurrence(s). See issues.json for evidence.
- **E0063 raised_render_surface** (candidate), room:chapel at [-11.65, -8.5521, -38.65]; 1 occurrence(s). See issues.json for evidence.
- **E0066 raised_render_surface** (candidate), room:chapel at [-11.65, -8.5573, -32.65]; 1 occurrence(s). See issues.json for evidence.
- **E0070 raised_render_surface** (candidate), room:chapel at [-7.65, -9.6375, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0071 raised_render_surface** (candidate), room:chapel at [-6.65, -9.6402, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0072 raised_render_surface** (candidate), room:chapel at [-4.65, -9.6239, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0073 raised_render_surface** (candidate), room:chapel at [0.35, -9.6388, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0075 raised_render_surface** (candidate), room:chapel at [1.35, -9.6404, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0077 raised_render_surface** (candidate), room:chapel at [4.35, -9.6333, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0080 raised_render_surface** (candidate), room:chapel at [8.35, -9.6416, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0081 raised_render_surface** (candidate), room:chapel at [9.35, -9.6418, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0083 raised_render_surface** (candidate), room:chapel at [10.35, -9.6338, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0084 raised_render_surface** (candidate), room:chapel at [11.35, -9.6375, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0086 raised_render_surface** (candidate), room:chapel at [12.35, -9.6333, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0088 raised_render_surface** (candidate), room:chapel at [15.35, -9.6308, -24.65]; 1 occurrence(s). See issues.json for evidence.
- **E0091 raised_render_surface** (candidate), room:chapel at [16.35, -9.6378, -25.65]; 1 occurrence(s). See issues.json for evidence.
- **E0093 raised_render_surface** (candidate), room:chapel at [17.35, -9.6295, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0094 raised_render_surface** (candidate), room:nave at [-13.65, -17.6762, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0096 raised_render_surface** (candidate), room:nave at [-13.65, -17.6707, 30.35]; 1 occurrence(s). See issues.json for evidence.
- **E0098 raised_render_surface** (candidate), room:nave at [-13.65, -16.8031, 32.35]; 1 occurrence(s). See issues.json for evidence.
- **E0101 raised_render_surface** (candidate), room:nave at [-13.65, -17.6751, 34.35]; 1 occurrence(s). See issues.json for evidence.
- **E0103 raised_render_surface** (candidate), room:nave at [-13.65, -17.6752, 35.35]; 1 occurrence(s). See issues.json for evidence.
- **E0105 raised_render_surface** (candidate), room:nave at [-13.65, -17.393, 36.35]; 1 occurrence(s). See issues.json for evidence.
- **E0106 raised_render_surface** (candidate), room:nave at [-13.65, -17.6748, 37.35]; 1 occurrence(s). See issues.json for evidence.
- **E0108 raised_render_surface** (candidate), room:nave at [-13.65, -17.6664, 38.35]; 1 occurrence(s). See issues.json for evidence.
- **E0110 raised_render_surface** (candidate), room:nave at [-13.65, -17.6812, 39.35]; 1 occurrence(s). See issues.json for evidence.
- **E0111 raised_render_surface** (candidate), room:nave at [-13.65, -17.6761, 40.35]; 1 occurrence(s). See issues.json for evidence.
- **E0112 raised_render_surface** (candidate), room:nave at [-13.65, -17.6757, 42.35]; 1 occurrence(s). See issues.json for evidence.
- **E0114 raised_render_surface** (candidate), room:nave at [-13.65, -17.675, 43.35]; 1 occurrence(s). See issues.json for evidence.
- **E0116 raised_render_surface** (candidate), room:nave at [-13.65, -17.6749, 44.35]; 1 occurrence(s). See issues.json for evidence.
- **E0120 raised_render_surface** (candidate), room:nave at [-6.65, -17.6785, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0121 raised_render_surface** (candidate), room:nave at [-5.65, -17.6751, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0126 raised_render_surface** (candidate), room:nave at [-0.65, -17.6723, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0127 raised_render_surface** (candidate), room:nave at [0.35, -17.6696, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0129 raised_render_surface** (candidate), room:nave at [3.35, -17.6707, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0131 raised_render_surface** (candidate), room:nave at [4.35, -16.513, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0136 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.5217, -38.65]; 1 occurrence(s). See issues.json for evidence.
- **E0137 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7671, -37.65]; 1 occurrence(s). See issues.json for evidence.
- **E0138 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7583, -36.65]; 1 occurrence(s). See issues.json for evidence.
- **E0139 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7628, -35.65]; 1 occurrence(s). See issues.json for evidence.
- **E0140 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.758, -32.65]; 1 occurrence(s). See issues.json for evidence.
- **E0141 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7621, -31.65]; 1 occurrence(s). See issues.json for evidence.
- **E0143 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.75, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0145 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7623, -29.65]; 1 occurrence(s). See issues.json for evidence.
- **E0150 raised_render_surface** (candidate), room:ossuary at [-36.65, -9.7656, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0153 raised_render_surface** (candidate), room:ossuary at [-34.65, -9.7608, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0154 raised_render_surface** (candidate), room:ossuary at [-32.65, -9.7651, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0156 raised_render_surface** (candidate), room:ossuary at [-28.65, -9.765, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0157 raised_render_surface** (candidate), room:ossuary at [-27.65, -9.7593, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0159 raised_render_surface** (candidate), room:ossuary at [-26.65, -9.7637, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0161 raised_render_surface** (candidate), room:ossuary at [-24.65, -9.7584, -25.65]; 1 occurrence(s). See issues.json for evidence.
- **E0165 raised_render_surface** (candidate), room:bones at [-41.65, -9.6802, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0166 raised_render_surface** (candidate), room:bones at [-38.65, -9.6825, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0167 raised_render_surface** (candidate), room:bones at [-37.65, -9.678, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0168 raised_render_surface** (candidate), room:bones at [-36.65, -8.4235, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0170 raised_render_surface** (candidate), room:bones at [-30.65, -9.6778, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0171 raised_render_surface** (candidate), room:bones at [-29.65, -9.6812, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0173 raised_render_surface** (candidate), room:bones at [-28.65, -9.6803, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0174 raised_render_surface** (candidate), room:bones at [-27.65, -9.6848, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0175 raised_render_surface** (candidate), room:bones at [-26.65, -9.6862, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0176 raised_render_surface** (candidate), room:bones at [-25.65, -9.3496, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0177 raised_render_surface** (candidate), room:bones at [-24.65, -9.6764, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0178 raised_render_surface** (candidate), room:bones at [-23.65, -9.6868, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0180 raised_render_surface** (candidate), room:bones at [-22.65, -9.6836, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0183 raised_render_surface** (candidate), room:window at [-27.15, -9.7155, -8.65]; 1 occurrence(s). See issues.json for evidence.
- **E0184 raised_render_surface** (candidate), room:window at [-27.15, -9.7265, -7.65]; 1 occurrence(s). See issues.json for evidence.
- **E0185 raised_render_surface** (candidate), room:window at [-27.15, -9.7139, -6.65]; 1 occurrence(s). See issues.json for evidence.
