extends "res://content/environments/red_descent/h024_tunnels_v1/capture_inspection.gd"
## Actual map close views selected from the generated floor field audit.
func stone_room_views() -> Array[Array]:
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/environments/red_descent/h024_ground_v3/natural_v1/field-audit.json")) as Dictionary
	var result: Array[Array] = []
	for kind: String in ["earth","puddle"]:
		var site: Dictionary = (audit["views"] as Dictionary)[kind] as Dictionary
		var at: Array = site["at"] as Array
		var direction: Array = site["along"] as Array
		var point: Vector3 = Vector3(float(at[0]),float(at[1]),float(at[2]))
		var along: Vector3 = Vector3(float(direction[0]),0,float(direction[2]))
		result.append([kind+"-walk",point-along*2.2+Vector3.UP*1.6,point+along*1.0+Vector3.UP*.15,68.0])
		if kind == "puddle":result.append(["puddle-close",point-along*1.2+Vector3.UP*.85,point-Vector3.UP*.008,65.0])
	return result
