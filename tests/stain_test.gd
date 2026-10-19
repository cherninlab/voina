extends SceneTree

# Blood stains free themselves after STAIN_LIFE and with the scene. The capped list must drop
# those without touching a freed mark (a typed assignment of one is a script error).

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("STAIN_FAIL: " + message)

func valid(count: int) -> bool:
	if HitEffects.stains.size() != count:
		return false
	for stain: Variant in HitEffects.stains:
		if not is_instance_valid(stain):
			return false
	return true

func place(scene: Node3D, count: int) -> void:
	for index: int in range(count):
		HitEffects.place_stain(scene, Vector3(index * 0.1, 0.0, 0.0), Vector3.UP, Vector3.FORWARD, 0.3)

func run() -> void:
	var scene: Node3D = Node3D.new()
	root.add_child(scene)
	place(scene, HitEffects.MAX_STAINS + 10)
	check(valid(HitEffects.MAX_STAINS), "The list is capped at MAX_STAINS live marks")
	# The oldest marks expire on their own.
	for index: int in range(5):
		HitEffects.stains[index].free()
	place(scene, 1)
	check(valid(HitEffects.MAX_STAINS - 4), "Expired marks leave the list without freeing errors")
	# Leaving the game frees every mark with the scene.
	scene.free()
	scene = Node3D.new()
	root.add_child(scene)
	place(scene, 1)
	check(valid(1), "A new scene starts from its own marks")
	if failures == 0:
		print("STAIN_OK: capped at %d, expired and scene-freed marks dropped without errors" % HitEffects.MAX_STAINS)
	quit(0 if failures == 0 else 1)
