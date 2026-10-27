# Dungeon explorer run

Build `f85421d474f8c6e52eb97d654e16d413a930eeb1`; seed 186; mode fast.

Actual capsule visits: 1125 / 21402 sampled walkable cells.
Budget: 1800 physics ticks per explorer; 3 explorers. Unvisited cells are untested, not proven unreachable.

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
| room:antechamber | 129 | 548 |
| room:bell | 131 | 1348 |
| room:bones | 134 | 563 |
| room:cells | 0 | 472 |
| room:chapel | 0 | 2050 |
| room:choir | 94 | 2448 |
| room:entry | 0 | 712 |
| room:first_stair_hall | 117 | 593 |
| room:nave | 131 | 2151 |
| room:ossuary | 0 | 1222 |
| room:restraint | 0 | 1141 |
| room:second_stair_hall | 49 | 402 |
| room:window | 0 | 368 |
| route:bell_loop | 0 | 322 |
| route:cave_bypass | 0 | 342 |
| route:central_ledge | 0 | 615 |
| route:chapel_approach | 0 | 132 |
| route:choir | 0 | 2 |
| route:entry | 0 | 89 |
| route:first_stair | 0 | 385 |
| route:high_span | 0 | 433 |
| route:low_span | 0 | 637 |
| route:nave | 0 | 369 |
| route:ossuary_loop | 0 | 544 |
| route:return_gallery | 0 | 643 |
| route:return_stair | 132 | 942 |
| route:root_tunnel | 190 | 1052 |
| route:second_stair | 18 | 349 |
| route:upper_cells | 0 | 418 |
| route:upper_hall | 0 | 110 |

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

149 issue locations; 0 additional locations suppressed by the report cap.

- **E0001 enemy_stuck** (observed), fixture:unreachable-goal at [198.3291, 0.9009, 199.8741]; 1 occurrence(s). See issues.json for evidence.
- **E0149 stuck** (observed), room:choir at [30.4555, -27.1029, 11.9925]; 2 occurrence(s). See issues.json for evidence.
- **E0002 surface_backface_candidate** (candidate), room:entry at [-32.65, 0.0, -28.65]; 1 occurrence(s). See issues.json for evidence.
- **E0003 surface_backface_candidate** (candidate), room:entry at [-32.65, 5.0, -28.65]; 1 occurrence(s). See issues.json for evidence.
- **E0006 surface_backface_candidate** (candidate), room:antechamber at [-24.65, 5.5388, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0009 surface_backface_candidate** (candidate), room:restraint at [26.35, -0.0891, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0012 surface_backface_candidate** (candidate), room:cells at [30.35, -3.459, 3.35]; 1 occurrence(s). See issues.json for evidence.
- **E0014 surface_backface_candidate** (candidate), room:cells at [36.35, -2.497, 0.35]; 2 occurrence(s). See issues.json for evidence.
- **E0015 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.5357, -33.65]; 1 occurrence(s). See issues.json for evidence.
- **E0016 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.1592, -33.65]; 1 occurrence(s). See issues.json for evidence.
- **E0017 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.5416, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0018 surface_backface_candidate** (candidate), room:chapel at [-11.65, -8.1629, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0020 surface_backface_candidate** (candidate), room:chapel at [0.35, -1.371, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0022 surface_backface_candidate** (candidate), room:chapel at [9.35, 1.369, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0024 surface_backface_candidate** (candidate), room:chapel at [12.35, -7.6228, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0027 surface_backface_candidate** (candidate), room:nave at [-13.65, -3.4791, 34.35]; 1 occurrence(s). See issues.json for evidence.
- **E0029 surface_backface_candidate** (candidate), room:nave at [-13.65, -8.6723, 37.35]; 1 occurrence(s). See issues.json for evidence.
- **E0032 surface_backface_candidate** (candidate), room:nave at [-13.65, -13.204, 43.35]; 1 occurrence(s). See issues.json for evidence.
- **E0033 surface_backface_candidate** (candidate), room:nave at [-4.65, -17.6634, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0037 surface_backface_candidate** (candidate), room:ossuary at [-41.65, -5.8431, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0038 surface_backface_candidate** (candidate), room:ossuary at [-35.65, -9.4784, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0041 surface_backface_candidate** (candidate), room:ossuary at [-26.65, -4.6, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0045 surface_backface_candidate** (candidate), room:bones at [-29.65, -6.8438, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0048 surface_backface_candidate** (candidate), room:bones at [-23.65, -8.224, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0049 surface_backface_candidate** (candidate), room:window at [-27.15, -9.011, -9.65]; 1 occurrence(s). See issues.json for evidence.
- **E0052 surface_backface_candidate** (candidate), room:bell at [26.35, -16.4933, 38.35]; 2 occurrence(s). See issues.json for evidence.
- **E0053 surface_backface_candidate** (candidate), room:bell at [26.35, -16.4872, 41.35]; 2 occurrence(s). See issues.json for evidence.
- **E0059 surface_backface_candidate** (candidate), room:choir at [26.35, -26.6115, -0.65]; 1 occurrence(s). See issues.json for evidence.
- **E0060 surface_backface_candidate** (candidate), room:choir at [26.35, -10.8882, -0.65]; 1 occurrence(s). See issues.json for evidence.
- **E0061 surface_backface_candidate** (candidate), room:choir at [29.35, -10.04, 8.35]; 1 occurrence(s). See issues.json for evidence.
- **E0062 surface_backface_candidate** (candidate), room:choir at [29.35, -13.3263, 23.35]; 1 occurrence(s). See issues.json for evidence.
- **E0064 surface_backface_candidate** (candidate), room:choir at [32.35, -28.0, 23.35]; 1 occurrence(s). See issues.json for evidence.
- **E0066 surface_backface_candidate** (candidate), room:choir at [35.35, -23.5156, -12.65]; 1 occurrence(s). See issues.json for evidence.
- **E0067 surface_backface_candidate** (candidate), room:choir at [35.35, -14.7074, 23.35]; 1 occurrence(s). See issues.json for evidence.
- **E0068 surface_backface_candidate** (candidate), room:choir at [38.35, -26.144, -9.65]; 1 occurrence(s). See issues.json for evidence.
- **E0069 surface_backface_candidate** (candidate), room:choir at [38.35, -15.4567, 23.35]; 1 occurrence(s). See issues.json for evidence.
- **E0070 surface_backface_candidate** (candidate), room:choir at [44.35, -24.431, -9.65]; 1 occurrence(s). See issues.json for evidence.
- **E0071 surface_backface_candidate** (candidate), room:choir at [44.35, -28.0, -6.65]; 1 occurrence(s). See issues.json for evidence.
- **E0072 surface_backface_candidate** (candidate), room:choir at [44.35, -28.0, -0.65]; 1 occurrence(s). See issues.json for evidence.
- **E0073 surface_backface_candidate** (candidate), room:choir at [44.35, -22.3155, -0.65]; 1 occurrence(s). See issues.json for evidence.
- **E0074 surface_backface_candidate** (candidate), room:choir at [44.35, -28.0, 5.35]; 1 occurrence(s). See issues.json for evidence.
- **E0075 surface_backface_candidate** (candidate), room:choir at [44.35, -28.0, 11.35]; 1 occurrence(s). See issues.json for evidence.
- **E0076 surface_backface_candidate** (candidate), room:choir at [44.35, -18.6662, 14.35]; 1 occurrence(s). See issues.json for evidence.
- **E0077 surface_backface_candidate** (candidate), room:choir at [44.35, -17.9398, 17.35]; 1 occurrence(s). See issues.json for evidence.
- **E0078 surface_backface_candidate** (candidate), room:choir at [44.35, -28.0, 20.35]; 1 occurrence(s). See issues.json for evidence.
- **E0079 surface_backface_candidate** (candidate), room:choir at [44.35, -17.2157, 20.35]; 1 occurrence(s). See issues.json for evidence.
- **E0081 surface_backface_candidate** (candidate), room:first_stair_hall at [36.35, -10.0, -38.65]; 1 occurrence(s). See issues.json for evidence.
- **E0082 surface_backface_candidate** (candidate), room:first_stair_hall at [36.35, -10.0, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0083 surface_backface_candidate** (candidate), room:first_stair_hall at [39.35, -7.4666, -38.65]; 1 occurrence(s). See issues.json for evidence.
- **E0084 surface_backface_candidate** (candidate), room:first_stair_hall at [39.35, -10.0, -35.65]; 1 occurrence(s). See issues.json for evidence.
- **E0085 surface_backface_candidate** (candidate), room:first_stair_hall at [39.35, -7.0055, -35.65]; 1 occurrence(s). See issues.json for evidence.
- **E0086 surface_backface_candidate** (candidate), room:first_stair_hall at [39.35, -6.0301, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0087 surface_backface_candidate** (candidate), room:first_stair_hall at [42.35, -2.1964, -41.65]; 1 occurrence(s). See issues.json for evidence.
- **E0089 surface_backface_candidate** (candidate), room:second_stair_hall at [-36.15, -21.4446, 26.85]; 2 occurrence(s). See issues.json for evidence.
- **E0092 surface_backface_candidate** (candidate), room:second_stair_hall at [-27.15, -20.5953, 20.85]; 1 occurrence(s). See issues.json for evidence.
- **E0093 surface_backface_candidate** (candidate), room:second_stair_hall at [-27.15, -20.1877, 26.85]; 1 occurrence(s). See issues.json for evidence.
- **E0094 surface_backface_candidate** (candidate), room:second_stair_hall at [-27.15, -20.4443, 29.85]; 1 occurrence(s). See issues.json for evidence.
- **E0097 surface_backface_candidate** (candidate), route:entry at [-22.0, -0.32, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0099 surface_backface_candidate** (candidate), route:high_span at [-22.0, -0.32, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0100 surface_backface_candidate** (candidate), route:high_span at [-18.4031, 0.0, -16.6512]; 1 occurrence(s). See issues.json for evidence.
- **E0110 surface_backface_candidate** (candidate), route:nave at [-11.848, -14.7647, 27.0]; 1 occurrence(s). See issues.json for evidence.
- **E0111 surface_backface_candidate** (candidate), route:nave at [-8.152, -14.1752, 27.0]; 1 occurrence(s). See issues.json for evidence.
- **E0113 surface_backface_candidate** (candidate), route:nave at [-8.8912, -14.9329, 25.5216]; 1 occurrence(s). See issues.json for evidence.
- **E0114 surface_backface_candidate** (candidate), route:nave at [-11.3333, -14.5668, 26.0]; 1 occurrence(s). See issues.json for evidence.
- **E0115 surface_backface_candidate** (candidate), route:nave at [-10.2245, -15.2599, 24.5216]; 1 occurrence(s). See issues.json for evidence.
- **E0117 surface_backface_candidate** (candidate), route:nave at [-15.7778, -19.0, 25.848]; 1 occurrence(s). See issues.json for evidence.
- **E0118 surface_backface_candidate** (candidate), route:nave at [-15.7778, -15.2001, 25.848]; 1 occurrence(s). See issues.json for evidence.
- **E0119 surface_backface_candidate** (candidate), route:nave at [-15.7778, -16.0402, 22.152]; 1 occurrence(s). See issues.json for evidence.
- **E0120 surface_backface_candidate** (candidate), route:nave at [-19.3333, -16.2552, 25.848]; 1 occurrence(s). See issues.json for evidence.
- **E0121 surface_backface_candidate** (candidate), route:nave at [-19.3333, -16.2582, 22.152]; 1 occurrence(s). See issues.json for evidence.
- **E0122 surface_backface_candidate** (candidate), route:nave at [-24.6667, -16.5973, 25.848]; 1 occurrence(s). See issues.json for evidence.
- **E0123 surface_backface_candidate** (candidate), route:nave at [-24.6667, -15.8979, 24.0]; 1 occurrence(s). See issues.json for evidence.
- **E0124 surface_backface_candidate** (candidate), route:nave at [-24.6667, -16.5953, 22.152]; 1 occurrence(s). See issues.json for evidence.
- **E0125 surface_backface_candidate** (candidate), route:root_tunnel at [-23.0, -16.8891, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0144 surface_backface_candidate** (candidate), route:ossuary_loop at [-19.68, -10.0, -18.0]; 1 occurrence(s). See issues.json for evidence.
- **E0145 surface_backface_candidate** (candidate), route:cave_bypass at [-44.538, -23.0, 12.2985]; 1 occurrence(s). See issues.json for evidence.
- **E0146 surface_backface_candidate** (candidate), route:cave_bypass at [-47.413, -23.0, 4.7179]; 1 occurrence(s). See issues.json for evidence.
- **E0147 surface_backface_candidate** (candidate), route:cave_bypass at [-47.413, -18.1, 4.7179]; 1 occurrence(s). See issues.json for evidence.
- **E0096 visible_ceiling_gap** (candidate), route:entry at [-19.9, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0098 visible_ceiling_gap** (candidate), route:entry at [-22.0, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0108 visible_ceiling_gap** (candidate), route:upper_hall at [24.0, -2.4, -10.0]; 1 occurrence(s). See issues.json for evidence.
- **E0116 visible_ceiling_gap** (candidate), route:nave at [-14.0, -17.4, 24.0]; 2 occurrence(s). See issues.json for evidence.
- **E0139 visible_ceiling_gap** (candidate), route:return_gallery at [23.575, -8.4, 10.0]; 1 occurrence(s). See issues.json for evidence.
- **E0140 visible_ceiling_gap** (candidate), route:return_gallery at [20.4286, -8.4, -8.4286]; 1 occurrence(s). See issues.json for evidence.
- **E0141 visible_ceiling_gap** (candidate), route:return_gallery at [21.6667, -8.4, -22.3333]; 1 occurrence(s). See issues.json for evidence.
- **E0148 visible_ceiling_gap** (candidate), route:cave_bypass at [-46.9845, -21.4, 2.8607]; 1 occurrence(s). See issues.json for evidence.
- **E0095 visible_floor_gap** (candidate), route:entry at [-19.9, 1.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0101 visible_floor_gap** (candidate), route:high_span at [-17.0, 1.25, -15.0]; 1 occurrence(s). See issues.json for evidence.
- **E0102 visible_floor_gap** (candidate), route:high_span at [-12.0, 0.9, -14.0]; 2 occurrence(s). See issues.json for evidence.
- **E0103 visible_floor_gap** (candidate), route:high_span at [-3.0, 0.2, -12.0]; 2 occurrence(s). See issues.json for evidence.
- **E0104 visible_floor_gap** (candidate), route:high_span at [0.0, -0.1, -13.5]; 1 occurrence(s). See issues.json for evidence.
- **E0105 visible_floor_gap** (candidate), route:high_span at [3.0, -0.4, -15.0]; 2 occurrence(s). See issues.json for evidence.
- **E0106 visible_floor_gap** (candidate), route:high_span at [15.0, -1.4, -15.0]; 2 occurrence(s). See issues.json for evidence.
- **E0107 visible_floor_gap** (candidate), route:high_span at [19.5, -1.9, -12.5]; 1 occurrence(s). See issues.json for evidence.
- **E0126 visible_floor_gap** (candidate), route:low_span at [-21.2, -21.6, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0127 visible_floor_gap** (candidate), route:low_span at [-17.6, -22.0, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0128 visible_floor_gap** (candidate), route:low_span at [-15.8, -22.2, -16.0]; 1 occurrence(s). See issues.json for evidence.
- **E0129 visible_floor_gap** (candidate), route:low_span at [-14.0, -22.4, -16.0]; 2 occurrence(s). See issues.json for evidence.
- **E0130 visible_floor_gap** (candidate), route:low_span at [-9.0, -22.9, -8.0]; 2 occurrence(s). See issues.json for evidence.
- **E0131 visible_floor_gap** (candidate), route:low_span at [-3.0, -23.4, 4.0]; 2 occurrence(s). See issues.json for evidence.
- **E0132 visible_floor_gap** (candidate), route:low_span at [5.0, -24.4, 9.0]; 2 occurrence(s). See issues.json for evidence.
- **E0133 visible_floor_gap** (candidate), route:low_span at [4.7862, -24.4, 7.5032]; 1 occurrence(s). See issues.json for evidence.
- **E0134 visible_floor_gap** (candidate), route:low_span at [6.75, -24.65, 8.75]; 1 occurrence(s). See issues.json for evidence.
- **E0135 visible_floor_gap** (candidate), route:low_span at [10.25, -25.15, 8.25]; 1 occurrence(s). See issues.json for evidence.
- **E0136 visible_floor_gap** (candidate), route:low_span at [12.0, -25.4, 8.0]; 2 occurrence(s). See issues.json for evidence.
- **E0137 visible_floor_gap** (candidate), route:low_span at [16.0, -25.7, 3.0]; 2 occurrence(s). See issues.json for evidence.
- **E0138 visible_floor_gap** (candidate), route:low_span at [17.8, -25.84, 3.6]; 1 occurrence(s). See issues.json for evidence.
- **E0004 raised_render_surface** (candidate), room:antechamber at [-27.65, 0.2831, -27.65]; 1 occurrence(s). See issues.json for evidence.
- **E0005 raised_render_surface** (candidate), room:antechamber at [-24.65, 0.281, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0007 raised_render_surface** (candidate), room:antechamber at [-21.65, 0.2895, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0008 raised_render_surface** (candidate), room:restraint at [26.35, -3.7195, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0010 raised_render_surface** (candidate), room:restraint at [32.35, -3.7169, -22.65]; 1 occurrence(s). See issues.json for evidence.
- **E0011 raised_render_surface** (candidate), room:restraint at [41.35, -3.8274, -4.65]; 1 occurrence(s). See issues.json for evidence.
- **E0013 raised_render_surface** (candidate), room:cells at [30.35, -3.7197, 6.35]; 1 occurrence(s). See issues.json for evidence.
- **E0019 raised_render_surface** (candidate), room:chapel at [0.35, -9.6388, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0021 raised_render_surface** (candidate), room:chapel at [9.35, -9.6418, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0023 raised_render_surface** (candidate), room:chapel at [12.35, -9.6333, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0025 raised_render_surface** (candidate), room:chapel at [15.35, -9.6308, -24.65]; 1 occurrence(s). See issues.json for evidence.
- **E0026 raised_render_surface** (candidate), room:nave at [-13.65, -17.6751, 34.35]; 1 occurrence(s). See issues.json for evidence.
- **E0028 raised_render_surface** (candidate), room:nave at [-13.65, -17.6748, 37.35]; 1 occurrence(s). See issues.json for evidence.
- **E0030 raised_render_surface** (candidate), room:nave at [-13.65, -17.6761, 40.35]; 1 occurrence(s). See issues.json for evidence.
- **E0031 raised_render_surface** (candidate), room:nave at [-13.65, -17.675, 43.35]; 1 occurrence(s). See issues.json for evidence.
- **E0034 raised_render_surface** (candidate), room:nave at [4.35, -16.513, 28.35]; 1 occurrence(s). See issues.json for evidence.
- **E0035 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.7583, -36.65]; 1 occurrence(s). See issues.json for evidence.
- **E0036 raised_render_surface** (candidate), room:ossuary at [-41.65, -9.75, -30.65]; 1 occurrence(s). See issues.json for evidence.
- **E0039 raised_render_surface** (candidate), room:ossuary at [-32.65, -9.7651, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0040 raised_render_surface** (candidate), room:ossuary at [-26.65, -9.7637, -42.65]; 1 occurrence(s). See issues.json for evidence.
- **E0042 raised_render_surface** (candidate), room:bones at [-41.65, -9.6802, -16.65]; 1 occurrence(s). See issues.json for evidence.
- **E0043 raised_render_surface** (candidate), room:bones at [-38.65, -9.6825, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0044 raised_render_surface** (candidate), room:bones at [-29.65, -9.6812, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0046 raised_render_surface** (candidate), room:bones at [-26.65, -9.6862, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0047 raised_render_surface** (candidate), room:bones at [-23.65, -9.6868, -19.65]; 1 occurrence(s). See issues.json for evidence.
- **E0050 raised_render_surface** (candidate), room:window at [-27.15, -9.7139, -6.65]; 1 occurrence(s). See issues.json for evidence.
- **E0051 raised_render_surface** (candidate), room:window at [-27.15, -9.077, -3.65]; 1 occurrence(s). See issues.json for evidence.
- **E0054 raised_render_surface** (candidate), room:bell at [26.35, -17.7208, 47.35]; 1 occurrence(s). See issues.json for evidence.
- **E0055 raised_render_surface** (candidate), room:bell at [38.35, -17.7179, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0056 raised_render_surface** (candidate), room:bell at [41.35, -17.7174, 29.35]; 1 occurrence(s). See issues.json for evidence.
- **E0057 raised_render_surface** (candidate), room:bell at [44.35, -17.7241, 47.35]; 1 occurrence(s). See issues.json for evidence.
- **E0058 raised_render_surface** (candidate), room:choir at [26.35, -27.6925, -6.65]; 1 occurrence(s). See issues.json for evidence.
- **E0063 raised_render_surface** (candidate), room:choir at [32.35, -27.691, -12.65]; 1 occurrence(s). See issues.json for evidence.
- **E0065 raised_render_surface** (candidate), room:choir at [35.35, -27.6958, -12.65]; 1 occurrence(s). See issues.json for evidence.
- **E0080 raised_render_surface** (candidate), room:first_stair_hall at [27.35, -8.4976, -26.65]; 1 occurrence(s). See issues.json for evidence.
- **E0088 raised_render_surface** (candidate), room:second_stair_hall at [-36.15, -21.452, 20.85]; 1 occurrence(s). See issues.json for evidence.
- **E0090 raised_render_surface** (candidate), room:second_stair_hall at [-33.15, -22.6632, 20.85]; 1 occurrence(s). See issues.json for evidence.
- **E0091 raised_render_surface** (candidate), room:second_stair_hall at [-27.15, -22.666, 20.85]; 1 occurrence(s). See issues.json for evidence.
- **E0109 raised_render_surface** (candidate), route:nave at [-6.0, -17.6842, 28.152]; 1 occurrence(s). See issues.json for evidence.
- **E0112 raised_render_surface** (candidate), route:nave at [-8.8912, -17.9479, 25.5216]; 1 occurrence(s). See issues.json for evidence.
- **E0142 raised_render_surface** (candidate), route:upper_cells at [35.68, -2.4464, 0.4286]; 1 occurrence(s). See issues.json for evidence.
- **E0143 raised_render_surface** (candidate), route:upper_cells at [34.0, -2.7911, 0.4286]; 1 occurrence(s). See issues.json for evidence.
