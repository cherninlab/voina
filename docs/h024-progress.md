# H-024 progress increment

Builder work is incomplete and not visually accepted. This increment publishes
verified source and generated assets so other agents can coordinate on main.
H-024, T-196 and the narrow H-023 landing work remain in progress on the
[hosted board](https://secha-agent-board.cherninlab.workers.dev).

Implemented: closed-template passage builds, actual-axis junction clearances,
hewn and timber-shored forms, varied profiles, continuous face-mapped rock,
shared paving and ramp fitting, floorless portal cores, clipped fallback floor,
bounded shaft-corner openings, separate stair coping, and a continuous nave
landing prototype. All ten enclosed routes and fourteen nodes were rebuilt from
source; the dependent gallery and passage growth were regenerated.

Verification on this increment: Godot 4.7.2 editor import; core smoke including
local two-process ENet; 1,234 m actual capsule traversal; structure check with
23 bearings, 184 members and four cloth pins; 69 normal and 28 inspection
captures; generator seam/cavity controls; 25 exported meshes reimported with
finite coordinates and no validation repair. The chapel regression retained a
bad mesh hitting a render-only wall at 2.888 m; the rebuilt passage clears that
ray for 20 m. Full crawler: 22/22 controls, 17,236/21,616 sampled cells visited,
415 candidate findings. Counts are capped in several categories and are not a
visual quality score. Thirty-one protected room/stair/wall/vascular GLBs remain
byte-identical. Capture and standalone test logs include shutdown resource-leak
warnings; the diagnostic wall probe also reports resources in use at exit.

Open: root-to-low-span turning interface and exposed void; some junction cut
edges and threshold/material changes;
nave support underside finish; weak lighting/dressing. Growth audit still flags
three walking-corridor vertices and ten vertices deeper than 1 cm into stone;
maximum sampled attachment gap is 0.059 m. Passing traversal does not resolve
these visual findings. No manual input, two-Mac Tailscale or performance
acceptance is claimed.

Detailed game captures and rejected iterations are retained in the private
worktree's `content/environments/red_descent/h024_tunnels_v1/`; review evidence
is published as a separate progress increment.

Cave striping follow-up: `h024_remaining_v2/README.md` records the same-camera
controls and colour-only correction; all non-colour GLB bytes are unchanged.


### Excavation relief / root turning increment

Root+cave walls and junctions now carry bounded actual rock relief with matching backing geometry. A contextual turning chamber closes the old root exit void and opens onto the unchanged low-span bridge. Full-depth arch, floor collision, fitted torch and low-span dependency metadata are included. Actual game 18-view normal + inspection sets, intermediate failures, generator/native-Jolt tests, 1,234m traversal, structure/import/smoke/export audits and protected31 hashes: `content/environments/red_descent/h024_remaining_v2/README.md`. The remaining lighting/material seams and nave support underside are not accepted or hidden.


### Current cavity and underside repair

Current review: `content/environments/red_descent/h024_remaining_v2/cavity-final/review.html`. Complete cavity-derived rock, recessed matching backing and shared join collars close the newly exposed webs and remove backing crossings. Actual relief remains, with fixed floor and constrained seams. The nave support's 260-stone intrados is shipped separately. Final repeated import/smoke, 1,234m traversal, structure, 22 unchanged crawler controls, coverage/roof/native-turn rays, generator and25export audits pass. Protected31 assets remain identical. The full crawler spatial survey was not repeated. Fine seams, material/threshold transitions and two root vertices deeper than1cm remain review/cleanup items; broader bridge/shaft acceptance remains open.
