class_name LongGrassSettings
extends Resource
## Every knob of the Long Grass generator (gameplay/environment/long_grass.gd). Edit
## long_grass.tres in the inspector or as text. The file is part of the build fingerprint, so host
## and joiners always generate the same road; change it on both machines (ship it) before playing.

@export_group("Road")
## Same seed, same road. Change it for a new layout with the same feel.
@export var road_seed: int = 1337
## Walking length in metres.
@export_range(150.0, 3000.0, 10.0) var length: float = 900.0
## Distance between road points; the road bends only at these points.
@export_range(1.0, 10.0, 0.5) var step: float = 3.0
## Largest random change of direction per point, in degrees.
@export_range(0.0, 30.0, 0.5) var turn: float = 7.0
## How strongly the road returns to its overall direction (0 = free wander, 1 = straight).
@export_range(0.0, 1.0, 0.01) var straighten: float = 0.06
## The road never points further than this from its overall direction, in degrees.
@export_range(0.0, 85.0, 1.0) var max_heading: float = 55.0
## Width of the trodden path.
@export_range(1.0, 8.0, 0.1) var path_width: float = 2.6

@export_group("Field")
## Tall grass fills this far from the road's centre line on each side; an invisible fence stops
## players there.
@export_range(6.0, 40.0, 0.5) var field_half_width: float = 18.0
@export_range(0.5, 4.0, 0.05) var grass_height_min: float = 1.6
@export_range(0.5, 4.0, 0.05) var grass_height_max: float = 2.5
## Grass clumps per square metre (each clump is several blades).
@export_range(0.1, 4.0, 0.05) var grass_density: float = 1.2
## Grass beyond this many metres from the camera is not drawn.
@export_range(20.0, 200.0, 5.0) var grass_view_distance: float = 75.0
@export var grass_root: Color = Color(0.05, 0.08, 0.06)
@export var grass_tip: Color = Color(0.32, 0.4, 0.33)
## Sway amplitude of the blade tips in metres.
@export_range(0.0, 0.6, 0.01) var wind: float = 0.18

@export_group("Treeline")
## Dark spruce silhouettes on the horizon, beyond the fence: this near and far from the road.
@export_range(25.0, 300.0, 5.0) var trees_near: float = 60.0
@export_range(30.0, 400.0, 5.0) var trees_far: float = 160.0
## Road metres between rows of three trees on each side; smaller is a denser wood.
@export_range(1.0, 30.0, 0.5) var tree_spacing: float = 5.0
## Share of the horizon left open between stands of trees (0 = an unbroken wall of wood).
@export_range(0.0, 0.9, 0.05) var tree_gaps: float = 0.35
@export_range(3.0, 40.0, 0.5) var tree_height_min: float = 9.0
@export_range(3.0, 40.0, 0.5) var tree_height_max: float = 19.0
## Multiplies the pine sprites' own colours: low keeps them a dark wood against the night sky.
@export var tree_tint: Color = Color(0.13, 0.15, 0.17)

@export_group("Camps")
## Where the first clearing sits along the road, in metres.
@export_range(20.0, 500.0, 5.0) var first_camp: float = 90.0
## Average road distance between clearings; each spacing varies by +/- camp_jitter.
@export_range(40.0, 600.0, 5.0) var camp_spacing: float = 150.0
@export_range(0.0, 200.0, 5.0) var camp_jitter: float = 40.0
@export_range(4.0, 20.0, 0.5) var camp_radius: float = 9.0
## Cultists at the first camp, then camp_growth more per camp (rounded down), capped at
## cultists_max. The road ends in a last clearing around a fire, which always holds cultists_max.
@export_range(1, 8, 1) var cultists_first: int = 2
@export_range(0.0, 3.0, 0.1) var camp_growth: float = 0.5
@export_range(1, 8, 1) var cultists_max: int = 5
## A camp wakes when a player comes this close to its fire.
@export_range(10.0, 60.0, 1.0) var wake_distance: float = 32.0

@export_group("Night")
## Compass direction of the moon (0 = straight ahead along the road) and its height, in degrees.
@export_range(-180.0, 180.0, 1.0) var moon_yaw: float = 25.0
@export_range(5.0, 85.0, 1.0) var moon_height: float = 32.0
## Apparent moon radius in degrees (the real moon is 0.26; a bigger one reads better on screen).
@export_range(0.2, 6.0, 0.05) var moon_size: float = 2.2
@export_range(0.0, 2.0, 0.01) var moonlight: float = 0.45
@export_range(0.0, 0.1, 0.001) var fog_density: float = 0.022
