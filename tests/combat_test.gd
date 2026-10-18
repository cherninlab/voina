extends SceneTree

var attacker: CombatController = CombatController.new()
var defender: CombatController = CombatController.new()
var shooter: CombatController = CombatController.new()
var active_hits: Array[bool] = []

func _initialize() -> void:
	call_deferred("run")

func advance(combat: CombatController, seconds: float) -> void:
	for tick: int in range(int(ceil(seconds * 120))):
		combat.step(1.0 / 120.0)

func run() -> void:
	root.add_child(attacker)
	root.add_child(defender)
	attacker.set_physics_process(false)
	defender.set_physics_process(false)
	attacker.attack_active.connect(func(ranged: bool) -> void: active_hits.append(ranged))
	assert(attacker.begin_attack(false))
	assert(not attacker.begin_attack(true), "Attack spam cannot bypass windup")
	assert(defender.set_block(true))
	assert(defender.take_hit(25, false, true, attacker) == CombatController.HitResult.PARRY)
	assert(defender.health == 100 and attacker.phase == CombatController.Phase.STAGGERED)
	advance(attacker, 1.0)
	assert(active_hits.is_empty(), "A parried windup never resolves later")
	advance(defender, 0.25)
	assert(defender.take_hit(25, false, true) == CombatController.HitResult.BLOCK)
	assert(defender.health == 95 and is_equal_approx(defender.stamina, 80.0))
	assert(defender.take_hit(25, false, false) == CombatController.HitResult.HIT)
	assert(defender.health == 70, "Rear attacks bypass block")
	defender.stamina = 0.0
	assert(defender.take_hit(25, false, true) == CombatController.HitResult.HIT)
	assert(not defender.blocking and defender.phase == CombatController.Phase.STAGGERED, "Exhausted guard breaks")
	defender.respawn()
	advance(defender, 0.6)
	assert(defender.begin_dash())
	assert(not defender.begin_dash() and is_equal_approx(defender.stamina, 65.0))
	assert(defender.take_hit(15, true, true) == CombatController.HitResult.EVADE)
	assert(defender.take_hit(25, false, true) == CombatController.HitResult.HIT, "Dash does not evade melee")
	advance(defender, 0.17)
	assert(defender.take_hit(15, true, true) == CombatController.HitResult.HIT, "Ranged immunity expires before dash ends")
	assert(not defender.set_block(true), "Cannot block during dash")
	advance(defender, 0.9)
	assert(defender.phase == CombatController.Phase.IDLE and defender.stamina > 65.0)
	defender.stamina = 1.0
	assert(not defender.begin_attack(false) and not defender.begin_dash())
	defender.respawn()
	advance(defender, 0.6)
	assert(defender.begin_attack(false))
	defender.take_hit(200, true, true)
	advance(defender, 0.5)
	assert(defender.health == 100 and defender.phase == CombatController.Phase.IDLE)
	assert(attacker.begin_attack(false))
	advance(attacker, 0.14)
	assert(active_hits.is_empty(), "Windup has no hitbox")
	advance(attacker, CombatController.MELEE_ACTIVE + 0.02)
	assert(active_hits.size() >= 10 and not active_hits.has(true), "Melee sweeps every active tick")
	assert(attacker.strike(7) and not attacker.strike(7) and attacker.strike(8), "One hit per target per swing")
	var swept: int = active_hits.size()
	advance(attacker, 0.5)
	assert(active_hits.size() == swept and attacker.phase == CombatController.Phase.IDLE, "Recovery has no hitbox")
	assert(attacker.begin_attack(false) and attacker.strike(7), "A new swing clears struck targets")
	defender.respawn()
	advance(defender, 0.6)
	assert(defender.set_block(true))
	advance(defender, 0.22)
	assert(defender.take_hit(25, false, true, null, 0.05) == CombatController.HitResult.PARRY, "Latency grace extends parry")
	defender.respawn()
	advance(defender, 0.6)
	assert(defender.set_block(true))
	advance(defender, 0.3)
	assert(defender.take_hit(25, false, true, null, 5.0) == CombatController.HitResult.BLOCK, "Grace is capped")
	root.add_child(shooter)
	shooter.set_physics_process(false)
	assert(shooter.begin_shot(12.0, 0.6))
	assert(not shooter.begin_shot(12.0, 0.6) and not shooter.begin_attack(true), "Bolts share the attack cooldown")
	advance(shooter, 0.62)
	assert(shooter.phase == CombatController.Phase.IDLE and is_equal_approx(shooter.stamina, 88.0), "A bolt costs stamina and releases quickly")
	shooter.stamina = 5.0
	assert(not shooter.begin_shot(12.0, 0.6), "A bolt needs stamina")
	shooter.respawn()
	advance(shooter, 0.6)
	assert(shooter.set_block(true) and not shooter.begin_shot(12.0, 0.6), "Cannot fire while blocking")
	assert(shooter.parries(true) and not shooter.parries(false), "A fresh front block parries")
	advance(shooter, 0.22)
	assert(not shooter.parries(true) and shooter.parries(true, 0.05), "Parry grace extends the window")
	shooter.set_block(false)
	advance(shooter, 0.4)
	assert(shooter.begin_dash() and shooter.evades_ranged(), "Dash start evades ranged")
	advance(shooter, 0.17)
	assert(not shooter.evades_ranged(), "Ranged immunity expires")
	assert(CombatController.guards(0.0, Vector3.BACK) and not CombatController.guards(0.0, Vector3.FORWARD), "Guard faces incoming from the front only")
	var paused: CombatController = CombatController.new()
	root.add_child(paused)
	paused.set_physics_process(false)
	paused.attack_active.connect(func(ranged: bool) -> void: active_hits.append(ranged))
	assert(paused.begin_attack(false))
	paused.frozen = true
	assert(not paused.strike(99), "A round freeze rejects remaining targets in the current sweep")
	var before_freeze: int = active_hits.size()
	advance(paused, 1.0)
	assert(active_hits.size() == before_freeze and paused.phase == CombatController.Phase.IDLE, "A frozen windup never resolves or resumes")
	assert(not paused.set_block(true), "Guard cannot be raised during a round freeze")
	paused.frozen = false
	assert(paused.begin_attack(false))
	advance(paused, 0.16)
	paused.frozen = true
	before_freeze = active_hits.size()
	advance(paused, 0.5)
	assert(active_hits.size() == before_freeze, "A freeze also cancels an already active attack")
	paused.frozen = false
	assert(paused.begin_dash())
	paused.frozen = true
	paused.step(0.01)
	assert(not paused.evades_ranged() and paused.phase == CombatController.Phase.IDLE, "A freeze cancels dash immunity")
	check_cut_follow_through()
	print("COMBAT_OK: parry, latency grace, recovery, block, guard break, stamina, dodge, active sweep, respawn cancellation, bolt release, capped cut follow-through")
	quit()

# Blade damage may outlast the 0.52 s swing while the host's stroke flies, but only for an
# approved melee swing, up to the cap, and never through block, dash, stagger, respawn or freeze.
func check_cut_follow_through() -> void:
	var cutter: CombatController = CombatController.new()
	root.add_child(cutter)
	cutter.set_physics_process(false)
	var swing: float = CombatController.MELEE_WINDUP + CombatController.MELEE_ACTIVE + CombatController.MELEE_RECOVERY
	assert(not cutter.cuts(true), "A live stroke without an approved swing never deals damage")
	assert(cutter.begin_attack(false))
	assert(cutter.cuts(false) and cutter.cuts(true), "The swing's own phases always cut")
	advance(cutter, swing + 0.02)
	assert(cutter.phase == CombatController.Phase.IDLE and is_equal_approx(cutter.stamina, 82.0))
	assert(cutter.cuts(true) and not cutter.cuts(false), "After recovery only a still-flying stroke cuts")
	assert(cutter.strike(5) and not cutter.strike(5), "Follow-through shares the swing's one hit per target")
	advance(cutter, CombatController.CUT_FOLLOW_THROUGH_CAP - swing)
	assert(not cutter.cuts(true), "Follow-through is capped even if the stroke never lands")
	assert(cutter.begin_attack(false) and cutter.strike(5), "The cooldown is unchanged and a new swing clears struck targets")
	var cancels: Array[Callable] = [
		func() -> void: cutter.stagger(),
		func() -> void: cutter.begin_dash(),
		func() -> void: cutter.set_block(true),
		func() -> void: cutter.respawn(),
		func() -> void: cutter.frozen = true,
	]
	for index: int in range(cancels.size()):
		cutter.respawn()
		cutter.frozen = false
		advance(cutter, 0.6)
		assert(cutter.begin_attack(false))
		advance(cutter, swing + 0.02)
		assert(cutter.cuts(true))
		cancels[index].call()
		# Long enough for a dash to end, still inside the cap: only the cancellation can stop it.
		advance(cutter, 0.26)
		cutter.blocking = false
		cutter.frozen = false
		assert(not cutter.cuts(true), "Cancellation %d ends the follow-through" % index)
	cutter.respawn()
	advance(cutter, 0.6)
	assert(cutter.begin_attack(true))
	advance(cutter, 0.1)
	assert(not cutter.cuts(true), "A ranged attack has no blade follow-through")
