# Dungeon explorer — verified run, 27 October 2026

[Open the full report and diagnostic camera table](20261027-full-v2/REPORT.md). Usage and limitations: [docs/dungeon-explorer.md](../../../../../docs/dungeon-explorer.md).

- Three actual player-scene capsules visited **17,190 / 21,402 sampled walkable cells (80.3%)**, across all **30 room/route areas**, with independently logged starts throughout the dungeon. This is not proof that every visited area connects to the entrance.
- **22/22 controls passed**, including a known visual hole above solid collision, reversed winding, an instanced floor, a physical fall, and actual enemy obstruction. Ten enemy scenarios include both real dungeon hall grids.
- **37 observed capsule snag locations** have contacts and motion traces. The controlled enemy scenarios also reproduce two false-arrival cases and two blocked-movement cases. These distinguish navigation/decision problems from suspected map defects; they are not 41 certified level bugs.
- **432 visual/layout candidates** remain for triage: 100 raised render surfaces, 100 possible backfaces, 100 missing visual floor probes, 100 missing collision-floor probes, 17 ceiling probes and 15 collision/visual height mismatches. Candidate locations are capped at 100 per kind; **1,220 additional locations were suppressed**. Some are intentional rubble, openings or board joints.
- **147 actual Mobile/Metal frames** cover six directions at each crawler's recorded pose plus three failure locations, with seven synchronized passes: color, stable object colors, depth, normals, surface crossings, collision and clearance. Thickness is omitted.

Start with the observed physical failures:

| Finding | Position | Evidence |
| --- | --- | --- |
| E0437, choir snag | (30.4555, -27.1029, 11.9925) | `StoneRoom_choir/Collision_choir_9`; [color](20261027-full-v2/E0437-color.png), [collision](20261027-full-v2/E0437-collision.png) |
| E0438, first stair snag | (38.1965, -6.6950, -38.7031) | Actual capsule stalls on the sloping walking collision; [color](20261027-full-v2/E0438-color.png), [object colors](20261027-full-v2/E0438-objects.png), [normals](20261027-full-v2/E0438-normals.png) |
| E0439, first stair hall snag | (41.4790, -9.0991, -39.9103) | `StoneRoom_first_stair_hall/Collision_first_stair_hall_5`; [color](20261027-full-v2/E0439-color.png), [collision](20261027-full-v2/E0439-collision.png) |

[issues.json](20261027-full-v2/issues.json) has complete evidence and replay commands. [objects.json](20261027-full-v2/objects.json) maps colors to node paths, mesh assets, triangle counts, explicit LOD ranges and MultiMesh instance counts. Its 16.52 million stored triangles include explicit LODs and instances; they are not a simultaneous GPU workload or a frame-rate measurement. [travel-times.json](20261027-full-v2/travel-times.json) retains unchecked directions rather than inventing timings; only 10 of 62 directed area connections have connected observed-step estimates in this budget.

Detector fixes during iteration removed invalid camera probes inside geometry, recovered actual winding rather than ray-facing normals, included instanced surfaces, and recognized raised routes inside tall room volumes. The earlier full iteration is preserved outside the repository at `/tmp/dungeon-explorer-20261027-full-before-instance-fix`.

The final paired replay, editor import, core smoke and enemy smoke evidence is in [validation](validation/). Runtime enemy fixes and level fixes are follow-ups; this change supplies inspection and regression tools. Manual input, camera feel, two-Mac/Tailscale acceptance, and sustained rendering/thermal performance were not measured.
