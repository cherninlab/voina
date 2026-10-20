class_name RaiderMob
extends HostileMob
## A raider, the game's first PvE enemy, brought back beside the church yard's villagers: it lies
## in wait in the village or in the haunted forest along the church road (MobSystem.Zone). The host
## runs its brain: it holds its post, runs down any player it sees in its zone, and throws a
## telegraphed jab at close range. It gives up once its target leaves the zone or stays hidden, and
## walks back to its post.
## Uses the shared states IDLE, MOVE, ACT (windup, then the jab and its recovery) and DEAD only.

const RAIDER_WINDUP: float = 0.5
const RAIDER_RECOVERY: float = 0.8
const JAB_CONTACT: float = 0.19 # Punch_Jab's lead fist is fully out 0.19 s in (0.12 s blend included)
const REACH: float = 1.9
const STRIKE_RANGE: float = 1.65 # it stops and jabs from this close
const RAIDER_DAMAGE: int = 12
const SIGHT: PackedFloat32Array = [30.0, 22.0] # by zone: the forest fog swallows more
var zone: int = MobSystem.Zone.FOREST # replicated through the spawn data
const RUN_SPEED: float = 2.7
const RETURN_SPEED: float = 1.6

func _ready() -> void:
	visual.set("raider", true)
	super._ready()

# Raiders walk their zone's grid, not the church yard's.
func grid() -> MobNavigation:
	return system.raider_grids[zone]

# Players on the zone's grid are fair game; anyone beyond it is not.
func in_zone(point: Vector3) -> bool:
	return system != null and not grid().heights.is_empty() and grid().covers(point)

# Perception supplies a last-known position. Movement never reads a hidden target's position.
func sense() -> void:
	var nearest_distance: float = SIGHT[zone]
	var seen: CharacterBody3D
	for node: Node in system.players.get_children():
		var player: CharacterBody3D = node as CharacterBody3D
		if player == null or player.is_queued_for_deletion() or not in_zone(player.global_position):
			continue
		var distance: float = global_position.distance_to(player.global_position)
		if distance < nearest_distance and can_see(player):
			seen = player
			nearest_distance = distance
	if seen != null:
		# Keep the committed attack target until recovery ends.
		if state != State.ACT:
			target = seen
		last_seen = seen.global_position
		memory_left = MEMORY
	elif state != State.ACT and (memory_left <= 0.0 or (has_target() and not in_zone(target.global_position))):
		target = null
		memory_left = 0.0

func choose_action(delta: float) -> void:
	if state == State.ACT:
		attack_age += delta
		if not has_target():
			state = State.IDLE
			return
		if attack_age >= RAIDER_WINDUP and not did_strike:
			did_strike = true
			jab()
		if attack_age >= RAIDER_WINDUP + RAIDER_RECOVERY:
			state = State.IDLE
		return
	if not has_target() or memory_left <= 0.0:
		# Back to the post among the trees, then wait there facing the road.
		if walk(home, RETURN_SPEED, State.MOVE, delta):
			state = State.IDLE
		return
	if global_position.distance_to(last_seen) < STRIKE_RANGE and can_see(target):
		yaw = facing(target.global_position - global_position)
		state = State.ACT
		attack_age = 0.0
		did_strike = false
		route.clear()
		return
	if walk(last_seen, RUN_SPEED, State.MOVE, delta):
		state = State.IDLE

# The jab commits its facing at the start of the windup, then checks range, cone and cover again.
func jab() -> void:
	if combat.phase == CombatController.Phase.STAGGERED or not has_target():
		return
	var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	if HitResolver.in_cone(global_position, forward, target.global_position, REACH, deg_to_rad(45)) and can_see(target):
		target.call("receive_hit", RAIDER_DAMAGE, forward, false, self)

# A player who hurts a raider in its zone becomes its target at once, seen or not.
func provoke(attacker: CharacterBody3D) -> void:
	if system == null or attacker.get_parent() != system.players or not in_zone(attacker.global_position):
		return
	if state != State.ACT:
		target = attacker
	last_seen = attacker.global_position
	memory_left = MEMORY

func _process(_delta: float) -> void:
	visual.rotation.y = yaw
	# Hold the jab until its fist reaches full extension (JAB_CONTACT into the clip) as the strike lands.
	var shown: int = State.IDLE if state == State.ACT and attack_age < RAIDER_WINDUP - JAB_CONTACT else state
	visual.call("show_state", shown, combat.health, combat.phase == CombatController.Phase.STAGGERED, state == State.ACT and attack_age < RAIDER_WINDUP)
	if state == State.DEAD:
		collision.set_deferred("disabled", true)
