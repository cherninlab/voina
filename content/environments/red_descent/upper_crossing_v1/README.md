# Upper crossing, first in-game iteration

The gallery exterior now follows its barrel vault instead of exposing a flat mortar slab. New roofing stones cover the curved crown. The existing gallery interior, paving, and five collision meshes come from the original asset. The build checks their protected mortar vertices and collision vertex positions.

A locally reconstructed rock abutment breaks up the shaft wall beside the restraint hall. Its visual mesh is cut away from room interiors and walking ribbons with a 0.9 m lateral margin. It adds no collision. Existing shaft walls provide its backing.

The user’s references establish damp ruined brick, decayed plaster, hanging roots and deep shadow with restrained warm light. This is a first structural and material iteration toward that direction. The wider shaft walls, bridge presentation, bone architecture, and remaining landing seams still need separate review.

## Sources and generation

- `source/rock.png` is a project-created ImageGen reference. `provenance.json` records its hash and prompt.
- The actual mesh was generated locally on Apple MPS with the installed MIT TripoSG model, seed 42, 50 steps, and 2,048 tokens. No remote 3D service was used.
- Raw reconstruction had 2,870,744 triangles and small holes. The local raw GLB and latents are ignored by Git.
- `solidify_rock.py` fills the raw source into a solid monolith at 0.0125-unit voxel resolution, including directional filling of unwanted tunnels. It checks watertightness and Euler characteristic 2.
- `reduce_rock.py` uses a 0.0075-unit voxel shell and surface relaxation, then reduces the source to roughly 18,000 and 4,500 triangles. It produces unit-height Y-up GLBs.
- Placement booleans are followed by closed-shell rebuilding. `validate_asset.py` checks the actual exported GLBs independently: no boundary or nonmanifold edges, consistent face winding, outward shading normals, and unchanged gallery collision. The new roof and modified mortar masses are also checked for open edges.
- The roof exports per-stone grey variation directly; the generator’s temporary tone/freshness channels are not displayed as color. Roof AO is not baked in this iteration.
- `rock_cliff.glb` contains the carved in-game placements. The original project rock material supplies its surface texture. The reference image is not a recovered texture atlas.
- `source/TripoSG-LICENSE.txt`, the existing MPS patch, exact revisions, weight hashes and generation receipt preserve model provenance.

## Reproduce

Run the reconstruction with the existing local environment from this folder:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python generate_rock.py \
  --cl3d-root /Users/theochernin/Projects/CherninLab3D --seed 42 --steps 50 --name rock
```

Solidify the raw reconstruction before reducing it:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python solidify_rock.py
```

Run these Blender 5.2 commands from the project root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python-exit-code 1 \
  --python content/environments/red_descent/upper_crossing_v1/reduce_rock.py
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python-exit-code 1 \
  --python scripts/art/build_upper_crossing.py
```

Verify the exports with the same CherninLab3D Python environment:

```sh
/Users/theochernin/Projects/CherninLab3D/.venv/bin/python \
  content/environments/red_descent/upper_crossing_v1/validate_asset.py
```

The gallery replacement records both its source GLB hash and the route hash. If its source becomes stale, the game falls back to the original passage and reports a warning.

## Review

`review/before/` and `review/after/` contain the matched game cameras from:

```sh
scripts/godot_bg.sh --path . --script scripts/capture_bridges.gd -- \
  --dungeon --shading-ephemeral --upper-crossing --capture-dir=/absolute/review/path
```

`review/rock-front.png`, `rock-side.png`, and `rock-back.png` render the actual reduced mesh in neutral studio lighting. They are distinct from the generated reference. The diagnostic images reuse `tests/dungeon_explorer.gd` with the same three cameras: color, albedo, object IDs, 30 m and 65 m depth, normals, intersection candidates and collision. Green intersection markers include intentional contacts and are not an exhaustive defect verdict.

```sh
scripts/godot_bg.sh --path . \
  --script content/environments/red_descent/upper_crossing_v1/review/run_diagnostics.gd -- \
  --dungeon --shading-ephemeral --explorer-capture --explorer-output=/absolute/review/path
```

The separate 3,840 × 2,160 view uses a 106° lens:

```sh
scripts/godot_bg.sh --path . \
  --script content/environments/red_descent/upper_crossing_v1/review/capture_wide.gd -- \
  --dungeon --shading-ephemeral /absolute/upper-landing-4k.png
```

Validation receipts and logs are under `review/validation/`. Automated checks establish asset loading, collision traversal and combat/network regression. Human input, camera feel, two-Mac Tailscale behavior, sustained performance and art acceptance remain separate.

## Iteration 2 — exterior joins

Roof and exterior side stones are clipped by the same network mitre/room planes as the source passage. The roof is staggered by half a stone on alternating rings; joints have deeper backing. A bonded 986-stone exterior facing replaces the broad bare mortar strip. Original interior and five collision meshes are preserved. Matched cameras are under `review/iteration2/`; `review/issues.json` keeps the wider unfinished work explicit.

## Iteration 3 — local Krea material family

Three real offline Krea 2 generations provide neutral limestone, bedrock and aged lime-plaster surfaces. Sources, exact prompts, MLX metadata, pinned model/license provenance and deterministic finishing are in `materials/`. The existing stone geometry now shares the limestone face; the red nave retains its separate lime-plaster role. Roots use the existing licensed bark scan with high roughness, replacing smooth red gloss. Core/editor checks and seven engine camera captures are under `review/iteration3/`. Derived PBR channels are estimates and art acceptance remains separate.

## Iteration 4 — load paths and real shaft relief

Four east-shaft edges now have closed, sculpted relief solids rather than thin textured slab faces. Three room floors have real plinth thickness. Four continuous piers reach the shaft base, and three segmental masonry arches support the outer gallery. The new relief/support collision uses the same triangles as the render geometry. A runtime guard compares the source outline, route hashes and native-precision room polygons before replacing any wall.

Rock clearances now follow the arched passage envelope, retain floor bearing and use actual room roof heights. Two detached reconstruction fragments were removed. New mortar caps receive a grey vertex colour so a closed shoulder does not render as a black slit.

`review/check_structure.gd` checks 480 render/collision ray samples, current loading and stale route/room rejection. Full core smoke and 1,235 m traversal pass. Exported relief, plinths, supports and inferred rock all pass the independent topology checks. Seven matched cameras, 56 diagnostic frames and a 4K frame are under `review/iteration4/`. This inspection exposed a separate gallery underside bedding leak, retained in the issue register for the next increment.

## Iteration 5 — bonded gallery cement

The five gallery sections now export as one render object per section, with separate stone and cement material surfaces. Each cement core is a single connected closed tube around the open passage, including 0.28 m of floor bearing recessed 0.06 m below the paving. End faces follow the authoritative mitres. Older stone backs, deliberately omitted by the source libraries, are capped; the exported gallery has zero boundary/nonmanifold edges and consistent winding. This is a bonded assembly, not a Boolean fusion of every decorative stone.

The five original collision meshes retain their vertex positions; the continuous cement adds matching collision. Runtime paving bedding is also a closed sloped prism. Checks cover 270 cement and 480 shaft-relief surface/collision rays, current/stale asset guards, core smoke and 1,235 m of capsule walking.

`review/iteration5/bonded/` holds three matched actual-game captures. `review/iteration5/compare.html` compares the exact underside camera before/after without image retouching. The reported slit region had 63 bright pixels before and zero after, with fixed camera/exposure. This is a regression check for that seam, not proof that every map seam is repaired.

## Iteration 6 — quieter plaster and fibrous roots

Two neutral base-only Krea sources from the local evaluation are now integrated: quieter worn plaster and continuous root bark. Source prompts, seed-42 metadata and experiment/runtime receipts are preserved alongside the first material family. Existing plaster peeling and root meshes stay the same; plaster avoids double darkening and root normal detail follows the length UVs at high roughness. This improves the surfaces; root shapes and attachments still need refinement.

Editor/core checks pass. Seven matched engine cameras and a fresh 3,840 × 2,160 wide view are under `review/iteration6/after/`. The cement slit remains closed in this material pass. Parallel LoRA concepts are inspiration and were not substituted for actual game evidence.

## Iteration 7 — fitted upper landing

A continuous below-deck bearing and two bevelled masonry sockets seat the upper east bridge's end posts at their actual baked stations. The original walking ribbon remains above them. Three new closed meshes add only 100 triangles, with collision taken from the same render faces. Current/stale guards, 270 cement rays, 504 relief/junction rays, core smoke and fresh 1,235 m traversal pass. Matched colour, low bearing detail, 16 diagnostic frames and a fresh 4K image are under `review/iteration7/`. Other junctions and art refinements remain in the issue register.
