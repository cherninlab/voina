class_name CombatController
extends Node

signal attack_started(ranged: bool)
signal attack_active(ranged: bool)
signal respawn_requested

const MAX_HEALTH: int = 100
const MAX_STAMINA: float = 100.0
const DASH_COST: float = 35.0
const PARRY_WINDOW: float = 0.18
const MAX_PARRY_GRACE: float = 0.08
const MELEE_WINDUP: float = 0.15
const MELEE_ACTIVE: float = 0.12
const MELEE_RECOVERY: float = 0.25
const DASH_DURATION: float = 0.25
const I_FRAME_DURATION: float = 0.15

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY, STAGGERED, DASHING }
enum HitResult { HIT, BLOCK, PARRY, EVADE }

var health: int = MAX_HEALTH
var stamina: float = MAX_STAMINA
var poise: float = 100.0
var blocking: bool = false
var phase: int = Phase.IDLE
var clock: float = 0.0
var phase_until: float = 0.0
var next_attack: float = 0.0
var last_spend: float = -10.0
var block_started: float = -10.0
var next_block: float = 0.0
var invulnerable_until: float = 0.0
var action_ranged: bool = false
var struck: Dictionary[int, bool] = {}

func _ready() -> void:
	set_multiplayer_authority(1)

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		step(delta)

func step(delta: float) -> void:
	clock += delta
	if phase != Phase.IDLE and clock >= phase_until:
		match phase:
			Phase.WINDUP:
				phase = Phase.ACTIVE
				phase_until = clock + MELEE_ACTIVE
			Phase.ACTIVE:
				phase = Phase.RECOVERY
				phase_until = clock + (0.0 if action_ranged else MELEE_RECOVERY)
			_:
				phase = Phase.IDLE
	# Melee sweeps every tick of its active window; strike() keeps it to one hit per target.
	if phase == Phase.ACTIVE and not action_ranged:
		attack_active.emit(false)
	if not blocking and phase == Phase.IDLE and clock - last_spend >= 0.7:
		stamina = minf(MAX_STAMINA, stamina + 22.0 * delta)
		poise = minf(100.0, poise + 18.0 * delta)

func spend(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	last_spend = clock
	return true

# head_start back-dates a client's melee windup by the time its request spent in flight.
func begin_attack(ranged: bool, head_start: float = 0.0) -> bool:
	if not multiplayer.is_server() or phase != Phase.IDLE or blocking or clock < next_attack:
		return false
	if not spend(8.0 if ranged else 18.0):
		return false
	next_attack = clock + 0.5
	action_ranged = ranged
	struck.clear()
	phase = Phase.ACTIVE if ranged else Phase.WINDUP
	phase_until = clock + (0.05 if ranged else MELEE_WINDUP - clampf(head_start, 0.0, MELEE_WINDUP))
	attack_started.emit(ranged)
	if ranged:
		attack_active.emit(true)
	return true

func set_block(wants_block: bool) -> bool:
	if not multiplayer.is_server():
		return false
	if not wants_block:
		blocking = false
		return true
	if blocking:
		return true
	if phase != Phase.IDLE or stamina < 20.0 or clock < next_block:
		return false
	blocking = true
	block_started = clock
	next_block = clock + 0.35
	return true

func strike(target_id: int) -> bool:
	if struck.has(target_id):
		return false
	struck[target_id] = true
	return true

func begin_dash() -> bool:
	if not multiplayer.is_server() or phase != Phase.IDLE or not spend(DASH_COST):
		return false
	blocking = false
	phase = Phase.DASHING
	phase_until = clock + DASH_DURATION
	invulnerable_until = clock + I_FRAME_DURATION
	return true

func stagger(duration: float = 0.8) -> void:
	blocking = false
	phase = Phase.STAGGERED
	phase_until = clock + duration
	invulnerable_until = 0.0

# parry_grace pads the window by the defender's one-way latency, since their block input reached the host late.
func take_hit(damage: int, ranged: bool, facing_attacker: bool, attacker: CombatController = null, parry_grace: float = 0.0) -> int:
	if not multiplayer.is_server():
		return HitResult.EVADE
	if ranged and clock < invulnerable_until:
		return HitResult.EVADE
	if blocking and facing_attacker:
		if not ranged and clock - block_started <= PARRY_WINDOW + clampf(parry_grace, 0.0, MAX_PARRY_GRACE):
			if attacker != null:
				attacker.stagger()
			return HitResult.PARRY
		if spend(20.0):
			health -= maxi(1, int(ceil(damage * 0.2)))
			if health <= 0:
				respawn()
			return HitResult.BLOCK
		stagger()
	health -= damage
	poise = maxf(0.0, poise - (15.0 if ranged else 35.0))
	last_spend = clock
	if health <= 0:
		respawn()
	elif poise <= 0.0 or phase == Phase.WINDUP:
		poise = 100.0
		stagger()
	return HitResult.HIT

func respawn() -> void:
	health = MAX_HEALTH
	stamina = MAX_STAMINA
	poise = 100.0
	blocking = false
	phase = Phase.IDLE
	phase_until = 0.0
	invulnerable_until = 0.0
	next_attack = clock + 0.5
	next_block = clock + 0.35
	respawn_requested.emit()
