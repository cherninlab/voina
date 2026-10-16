class_name BladeContact
extends RefCounted

# Host-only contact between a player's simulated blade and hostile raiders. Sword physics stays
# cosmetic between players; raiders are host-owned, so the host's own view of each blade is
# authoritative for them. Damage still goes through the swing's one-hit-per-target rule.
const KICK_SPEED: float = 1.0 # blade point speed that shoves a raider, swing or not
const CUT_SPEED: float = 10.0 # blade point speed that bisects a raider
const DAMAGE: int = 25 # same as the cone hit; a cut is lethal
const REHIT: float = 0.45
const REACH: float = 0.4 + 0.06 # raider capsule radius plus blade half-width
var last_hit: Dictionary[int, float] = {}

static func closest_points(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> Array[Vector3]:
	# Closest points between segments a and b, plus the fraction along a (as x of a Vector3).
	var u: Vector3 = a1 - a0
	var v: Vector3 = b1 - b0
	var w: Vector3 = a0 - b0
	var a: float = u.dot(u)
	var b: float = u.dot(v)
	var c: float = v.dot(v)
	var d: float = u.dot(w)
	var e: float = v.dot(w)
	var denominator: float = a * c - b * b
	var s: float = 0.0
	var t: float = 0.0
	if denominator > 0.000001:
		s = clampf((b * e - c * d) / denominator, 0.0, 1.0)
	t = (b * s + e) / c if c > 0.000001 else 0.0
	if t < 0.0:
		t = 0.0
		s = clampf(-d / a, 0.0, 1.0) if a > 0.000001 else 0.0
	elif t > 1.0:
		t = 1.0
		s = clampf((b - d) / a, 0.0, 1.0) if a > 0.000001 else 0.0
	return [a0 + u * s, b0 + v * t, Vector3(s, t, 0.0)]

func sweep(attacker: CharacterBody3D, motion: HeavySwordMotion, swinging: bool, now: float) -> void:
	var attacker_combat: CombatController = attacker.get("combat") as CombatController
	for node: Node in attacker.get_tree().get_nodes_in_group("hostile_mobs"):
		var mob: HostileMob = node as HostileMob
		if mob == null or mob.is_queued_for_deletion() or mob.combat.health <= 0:
			continue
		if now - float(last_hit.get(mob.mob_id, -INF)) < REHIT:
			continue
		var axis_bottom: Vector3 = mob.global_position + Vector3.DOWN * 0.5
		var axis_top: Vector3 = mob.global_position + Vector3.UP * 0.5
		var closest: Array[Vector3] = closest_points(motion.hilt, motion.tip, axis_bottom, axis_top)
		if closest[0].distance_to(closest[1]) > REACH:
			continue
		# The blade point that touched moves with the tip, scaled by how far along the blade it is.
		var point_velocity: Vector3 = motion.tip_velocity * closest[2].x
		var speed: float = point_velocity.length()
		if speed < KICK_SPEED:
			continue
		last_hit[mob.mob_id] = now
		var direction: Vector3 = point_velocity / speed
		# Shoves happen on any contact; damage and cuts need an approved swing and share its
		# one-hit-per-target rule with the cone.
		var damaging: bool = swinging and attacker_combat != null and attacker_combat.strike(-mob.mob_id)
		mob.blade_hit(attacker, closest[0], direction, speed, damaging and speed >= CUT_SPEED, DAMAGE if damaging else 0, motion.blade_direction())
