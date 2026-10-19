class_name ChurchSite
extends RefCounted
## The hillside church north of the village: shared by its scenery, the torch-lit road and the
## possessed villagers that haunt its graveyard. Points are on the ground plane (x, z); heights come
## from the terrain under them. The ground rises northward past z = -112, so the church stands on
## the slope with its door facing back down the north trail toward the village gate (z = -26.5).

const DOOR: Vector2 = Vector2(-4.0, -112.0) # centre of the church's south door, which faces +Z
const NAVE_LENGTH: float = 16.0 # the nave runs north (-Z) from the door
const NAVE_WIDTH: float = 9.0
const YARD_CENTER: Vector2 = Vector2(-4.0, -103.0) # the graveyard in front of the door
const YARD_RADIUS: float = 16.0 # possessed villagers keep inside this ring
const ROAD_START_Z: float = -30.0 # just outside the north gate
const ROAD_END_Z: float = -90.0 # where the road reaches the graveyard

# The same curve as WoodlandVillage.north_trail_center, which clears the trail through the trees.
static func road_x(z: float) -> float:
	return -0.5 + sin(maxf(-z - 37.0, 0.0) * 0.055) * 4.0

static func in_yard(point: Vector3) -> bool:
	return Vector2(point.x, point.z).distance_to(YARD_CENTER) <= YARD_RADIUS
