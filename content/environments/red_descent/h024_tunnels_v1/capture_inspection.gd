extends "res://scripts/capture_dungeon.gd"
## Same game materials/cameras, with a neutral camera-mounted review light.
## Run through godot_bg.sh; normal-lighting captures remain separate.

func _initialize() -> void:
	super._initialize()
	inspection_light.call_deferred()

func inspection_light() -> void:
	while true:
		await process_frame
		var camera: Camera3D = root.get_camera_3d()
		if camera != null and camera.get_parent() == current_scene:
			# A fresh review light per view avoids carrying Mobile light selection
			# and shadow-atlas state across camera teleports in a capture sweep.
			var lamp: OmniLight3D
			var previous: Transform3D = Transform3D(Basis.IDENTITY,Vector3(INF,INF,INF))
			while is_instance_valid(camera):
				if camera.global_transform != previous:
					if is_instance_valid(lamp):lamp.free()
					lamp = OmniLight3D.new()
					lamp.name = "InspectionLight"
					lamp.light_color = Color(.88,.93,1.0)
					lamp.light_energy = 3.0
					lamp.omni_range = 12.0
					lamp.shadow_enabled = true
					camera.add_child(lamp)
					lamp.position = Vector3(.3,.4,0)
					previous = camera.global_transform
					print("INSPECTION_LIGHT: fresh neutral camera light at ",camera.global_position)
				await process_frame
			return
