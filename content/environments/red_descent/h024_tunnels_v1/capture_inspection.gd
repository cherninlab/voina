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
			var lamp: OmniLight3D = OmniLight3D.new()
			lamp.name = "InspectionLight"
			lamp.light_color = Color(.88, .93, 1.0)
			lamp.light_energy = 3.0
			lamp.omni_range = 12.0
			lamp.shadow_enabled = true
			camera.add_child(lamp)
			lamp.position = Vector3(.3, .4, 0)
			print("INSPECTION_LIGHT: neutral camera light; game lighting unchanged")
			return
