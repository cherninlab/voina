# Iteration 7 — upper east landing bearing

A closed bearing follows the exact high-span endpoint mitre below the walking surface. Two small bevelled stone sockets surround the baked end-post feet; their stations match the source bridge generator's edge tangent and 0.13 m clearance. They remain below the deck and use the same rendered triangles for collision. Socket UVs reuse the existing per-stone metre mapping.

The complete exported structure has 61 meshes and 117,364 triangles. All new nodes pass independent closed/winding/normal checks. Runtime checks pass 270/270 cement rays and 504/504 relief/junction rays. Fresh 1,235 m capsule traversal passes after sizing the sockets; core smoke also passes. Review output retains the engine's known exit-only texture/ObjectDB leak warnings.

`after/` contains the matched landing/underside, an additional low bearing detail and a fresh 4K landing. The first low camera was obstructed; only the revised camera is retained. `diagnostics/` contains 16 frames across the reported cement slit and the new bearing: colour, albedo, IDs, 30/65 m depth, normals, intersection samples and collision. Sampling is not an exhaustive intersection or art acceptance test.

Other bridge landings, gallery end framing, inferred-rock surface refinement and root branch/attachment shapes remain explicit in `review/issues.json`.
