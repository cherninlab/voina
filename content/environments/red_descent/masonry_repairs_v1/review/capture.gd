extends "res://content/environments/red_descent/upper_crossing_v1/review/capture_diagnostics.gd"

func review_passes() -> PackedStringArray:
	return PackedStringArray(["color", "albedo", "objects", "normals", "collision"])

func review_views() -> Array[Array]:
	return [
		["choir-joints", Vector3(32.15,-26.2,-4.3375), Vector3(36,-25.9,6.25),90.0],
		["choir-side", Vector3(39,-26.2,13), Vector3(42,-23,2),85.0],
		["first-stair-lower", Vector3(31,-8.2,-30), Vector3(29.5,-7,-39.5),90.0],
		["first-stair-upper", Vector3(39.5,-4.3,-30.5), Vector3(31.5,-6.5,-39.5),90.0],
		["second-stair-lower", Vector3(-34.025,-21.2,24.55), Vector3(-31,-20.9,28),90.0],
		["second-stair-side", Vector3(-32,-20,32), Vector3(-39,-18,27),90.0],
		["upper-junction", Vector3(25,-5.7,-13), Vector3(24.2,-4.6,-10.6),80.0],
		["choir-corner-close", Vector3(43.2,-15.1,20.5), Vector3(45.3,-15.1,22.5),65.0],
		["first-stair-coping", Vector3(39,-4.8,-33), Vector3(37.6,-6,-36),65.0],
		["gallery-grazing", Vector3(21.5,-8.4,-3), Vector3(22.5,-8.4,-10),72.0],
		["upper-landing", Vector3(16.7889,1.0086,-13.3896), Vector3(17.5219,0.464,-12.9824),90.0],
	]

func capture_views() -> void:
	if "--matte-core-control" in OS.get_cmdline_user_args():
		for node: Node in dungeon.find_children("*", "MeshInstance3D", true, false):
			if not ("StoneRoom_choir/" in String(node.get_path()) or "stair_hall/" in String(node.get_path())):
				continue
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh.material_override is ShaderMaterial:
				var material: ShaderMaterial = mesh.material_override.duplicate() as ShaderMaterial
				material.set_shader_parameter("wetness",0.0)
				material.set_shader_parameter("dry_roughness_min",0.96)
				material.set_shader_parameter("wet_roughness",0.96)
				material.set_shader_parameter("normal_strength",0.1)
				mesh.material_override = material
	await super.capture_views()
