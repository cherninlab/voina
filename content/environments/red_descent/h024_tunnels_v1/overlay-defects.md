# Theo’s marked overlap defects

This investigation follows the two annotated contact sheets supplied on 9 November 2026. The preceding review.html/REPORT.md is a historical checkpoint, not certification of the solid-stone rebuild now in progress. Source captures are 1440×900; contact-sheet positions were converted back to camera pixels. Marks identify regions: a single centre ray can hit background through a visible gap and is not proof of ownership of every neighbouring fragment.

| Mark | Camera | Finding before repair | Verification required |
| --- | --- | --- | --- |
| A1 (12.2%,3.7%) | cave_bypass_0-back | Mortar_node_-41_-23_14_20 is closer than both roof webs; the mortar masks the stones | Roof facing in front of recessed core; no visible coplanar stripes |
| A2 (9.7%,10.6%) | cave_bypass_0-back | Stone-arch_root_tunnel_7 collar sits in front of the hewn skin | Remove redundant passage collar; inspect neighbouring masonry |
| A3 (4.8%,23%) | cave_bypass_0-back | Cave and root flag meshes cover the same patch, about 7 mm apart vertically | One paving owner with bedding below |
| B1 (63%,80.7%) | nave_6-back | Mortar_node_-14_-19_24_20 lies in front of the roof facing | Recessed core and partitioned roof material |
| B2 (63.7%,95.7%) | nave_6-back | Node flag patch was horizontal over a falling mitred ribbon | Fit to the same subdivided triangles as the game; measure vertical clearance |
| B3 (86.6%,69%) | nave_0-forward | Marked ray hits existing Floor_nave stones, dirt below, then recessed ground; no second near-coincident passage flag hit | Dark floor response remains unresolved; inspect broader threshold region, do not claim an overlap fix from this ray |
| B4 (19.7%,58.7%) | chapel_approach_1-back | Stone-arch_chapel_approach_2 protrudes ahead of BondedGallery_4 | Correct shared opening cut; retain gallery collision |
| B5 (2.9%,63.8%) | chapel_approach_1-back | Node mortar and chapel facing are virtually coincident; library backs are open before volume cuts | Closed initial stone volumes and recessed core |
| B6 (12.4%,59.7%) | chapel_approach_1-back | Exact centre ray passes to first-stair-hall wall group 2; adjacent floating strip includes the chapel arch stump | Review region after proper cuts; protected stair bodies remain unchanged |
| B7 (10.1%,30.4%) | cave_bypass_2-back | Roof arch and mortar at node_-43_-23_-6 are virtually coplanar | Closed templates, recessed core, separate web ownership |

The actual mesh-ray evidence is [ten-marks-before.json](validation/ten-marks-before.json). Flat-color geometry controls are retained separately. Red is mortar, blue is hewn rock, grey is stone facing, green is timber. They deliberately remove texture and lighting and are diagnostic images only.

Confirmed implementation mechanisms:

- Rock mapping: use baked UVs, correcting the earlier stretched texture bug.
- Junction backing: carve a slightly larger chamber/opening and recess blind chamber ends behind the roof facing.
- Barrel crossings: earlier webs own the shared stone thickness, avoiding two roof shells in the same space.
- Rock transitions: room and junction masonry already supply arches; additional run-end collars were redundant and left cut stumps.
- Floor crossings: stable arrival order gives the overlapping patch to one route.
- Sloping bay: fit its flags to the exact 1.4 m subdivided mitred walking triangles.
- Stone volume cuts: rebuild with full-backed templates. Closing previously damaged merged meshes failed manifold assertions and was rejected; those failed repairs are not accepted exports.

No in-game acceptance, shipment, manual input, Tailscale, or performance claim is made here.
