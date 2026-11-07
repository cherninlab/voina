extends "res://tests/dungeon_traversal_test.gd"

func check(condition: bool, message: String) -> void:
	if not condition and player != null:
		for index: int in range(player.get_slide_collision_count()):
			var contact: KinematicCollision3D = player.get_slide_collision(index)
			print("TRAVERSAL_COLLIDER: ", contact.get_collider().get_path(), " ", contact.get_position(), " normal=", contact.get_normal())
	super.check(condition, message)
