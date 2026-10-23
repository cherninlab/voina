# Dungeon PBR revision

Original ambientCG PBR maps, retrieved 2026-10-23. All six assets are CC0 1.0 Universal. Modification and raw-file redistribution are permitted, including in a commercial game: https://docs.ambientcg.com/license/

No bitmap synthesis, recoloring or resampling was applied. The shader supplies world-space projection, material tint, layered wear and selective wetness. Original map pixels are preserved. Color uses sRGB; normal/roughness/AO/displacement/metalness use linear sampling. OpenGL normals are used without green-channel inversion.


Runtime families: Bricks089 provides coarse shaft masonry and exposed plaster substrate; Bricks083 supplies trim; Concrete012 supplies fine plaster; Rocks025 supplies walking stone; Wood035 supplies oak detail; Metal041B supplies iron including its metalness map. Marble Rock 03 by Amal Kumar (Poly Haven, CC0) supplies natural cave-rock detail. Provider records and file hashes are in `sources.json` and `marble_rock_sources.json`.

The materials combine albedo, OpenGL normals, roughness, AO where supplied, and near-camera height parallax. Shader masks blend exposed substrate, patchy dampness, algae and broad colour variation. Height parallax changes shading, not collision or silhouettes. Coarser shaft masonry uses a 0.22 repeats/metre art scale. Generated sculpted modules instead use their own reference colour and these shared detail normals/roughness; their geometry supplies the silhouette.

The original image-generated normal maps in other folders are retained as earlier studies; this revision uses calibrated provider PBR maps. No Textures.com or giveaway content is included.
