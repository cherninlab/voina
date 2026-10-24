# T-167: actual source-model review

18 CL3D-generated chunks, 54 explicit LOD files. Rows: six ashlar fragments; six rough rocks; three column drums then three brick clumps. The source manifest supplies exact ids, dimensions, hashes, origin, material hints and runtime parameters.

## Native clay captures

![18 actual imported source meshes](review/godot/all-chunks.png)

## Native paired-map material trials

![18 actual material trials](review/godot_textured/all-chunks.png)

These are real Godot Mobile/Metal screenshots, not ImageGen concept images. The final material trial uses the supplied metre-space UVs, verified tangents, normals/roughness/AO at small-fragment texel density, and no parallax. Individual 1280x720 captures are in each folder. Brick/mortar regions share one preview material; embedded GLBs retain neutral clay. Human visual approval and final in-dungeon appearance are pending.

Blender front/back contact sheets: [front](review/all-chunks-front.png), [back](review/all-chunks-back.png). [Source/material handoff and exact prompts](README.md), [manifest](manifest.json), [verification](review/verification.json).
