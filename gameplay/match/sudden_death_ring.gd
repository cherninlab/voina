class_name SuddenDeathRing
extends Node3D
## Sudden death after the round timer: a hazard ring closes on the arena centre over
## CLOSE_SECONDS. The radius is derived from MatchFlow's replicated time, so every peer draws the
## same ring without extra sync. Only the host burns fighters outside it, through CombatController.

const CLOSE_SECONDS: float = 15.0
const START_RADIUS: float = 17.0  # reaches the corners of the 24 m arena
const END_RADIUS: float = 1.5
const BURN_INTERVAL: float = 0.25
const BURN_DAMAGE: int = 5  # 20 health per second outside the ring

var burn_clock: float = 0.0
var shown_radius: float = START_RADIUS
var wall: MeshInstance3D = null

static func radius_at(time_left: float) -> float:
	return lerpf(END_RADIUS, START_RADIUS, clampf(time_left / CLOSE_SECONDS, 0.0, 1.0))

static func outside(body: Node3D, radius: float) -> bool:
	return Vector2(body.global_position.x, body.global_position.z).length() > radius

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 6.0
	mesh.radial_segments = 96
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.25, 0.15, 0.35)
	mesh.material = material
	wall = MeshInstance3D.new()
	wall.mesh = mesh
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position.y = 3.0
	wall.visible = false
	add_child(wall)

func reset() -> void:
	burn_clock = 0.0

# Host only: damage everyone outside the ring on a fixed cadence.
func burn(bodies: Array[CharacterBody3D], radius: float, delta: float) -> void:
	burn_clock += delta
	while burn_clock >= BURN_INTERVAL:
		burn_clock -= BURN_INTERVAL
		for body: CharacterBody3D in bodies:
			if outside(body, radius):
				(body.get("combat") as CombatController).take_environment_damage(BURN_DAMAGE)

# Visual only (a mesh, not a physics body), so scaling it is safe.
func display(active: bool, radius: float, delta: float) -> void:
	if wall == null:
		return
	wall.visible = active
	if not active:
		shown_radius = START_RADIUS
		return
	shown_radius = lerpf(shown_radius, radius, minf(1.0, delta * 12.0))
	wall.scale = Vector3(shown_radius, 1.0, shown_radius)
