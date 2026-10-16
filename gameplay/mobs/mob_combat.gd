extends CombatController

# Mobs share guard/poise/stagger rules, but zero health means death, not player respawn.
func respawn() -> void:
	health = 0
	blocking = false
	phase = Phase.STAGGERED
	phase_until = INF
	respawn_requested.emit()
