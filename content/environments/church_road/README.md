# Church road torches

Original SECHA shaders for the torch stakes and wet mud along the north trail (`gameplay/environment/church_road.gd`, see `docs/church-road.md`). Written for this project on 2026-10-19; no external code, textures, meshes or sounds.

- `torch_flame.gdshader`: upright camera-facing flame; scrolling value-noise fbm tears a teardrop body into tongues, heat ramp deep red to orange to a yellow core, premultiplied blend.
- `torch_halo.gdshader`: soft additive glow around each flame (stands in for bloom and lit fog).
- `torch_head.gdshader`: charred pitch-rag head with ember cracks and a glowing coal rim; `heat` 0 is cold, about 0.3 smouldering.
- `torch_spark.gdshader`, `torch_smoke.gdshader`: draw passes for the CPU ember and smoke particles.
- `road_mud.gdshader`: wet trodden mud with ruts and a few dark puddles, broken soft shoulders.

Reused textures, provenance unchanged in `content/environments/village_generated/provenance.json`: `aged_timber.png` (stakes), `mineral_earth.png` and `soil_gravel.png` (mud). Stake, head and overlay geometry is generated in code.
