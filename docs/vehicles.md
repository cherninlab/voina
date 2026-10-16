# Parked cars (GGBot PSX Style Cars)

**PSX Style Cars** by GGBot, August 2023 release, is imported in `content/vehicles/ggbot_psx_cars/`. The archive has no license file. The [itch.io page](https://ggbot.itch.io/psx-style-cars) states the assets are licensed under **CC0 1.0 Universal**. The archive hash, the license source and per-file SHA-256 hashes are in `provenance.json`.

Included (unmodified except one case fix: `Car 03/Car3.mtl` named `Car3.png`, but the supplied file is `car3.png`, which broke loading on Linux): Car 01–08 OBJ/MTL meshes (with police and taxi variants of Car 05) and all their 128 px PNG skins (PNGs via Git LFS). Each car mesh already contains its wheels. Omitted: `.blend` sources, the sound effects, the separate wheel and blob-shadow meshes. Add them from the original zip when a feature needs them.

## Use

`CarProp.create("Car 05/Car5_Police.obj", "Car 05/car5_police.png")` returns a `StaticBody3D`; set its position and yaw and add it to the scene. `match_world.gd` `add_parked_cars()` parks four as cover: police, burned-out, taxi and 1920s.

- **Scale:** the source cars are about 1.5× real size, so the visual is uniformly scaled by 0.65. A sedan is about 4.8 m long and 1.4 m tall.
- **Collision:** a convex hull built from the scaled mesh points; the body itself is never scaled. Cars block beams and melee line of sight below roof height.
- **Textures:** they use nearest-neighbour filtering for the PSX look. The OBJ importer warns that the MTL ambient (`Ka`, `map_Ka`) entries are ignored; `CarProp` replaces the imported material anyway.

## Check

`tests/car_test.gd` (run by `scripts/smoke_test.py`) imports all 10 models with a skin, checks car-like dimensions, and checks that a parked car stops a chest-height ray but not one above the roof. A rendered screenshot on the development Mac confirmed textures, facing and placement. Cars as driveable vehicles are not implemented.
