extends Node3D
## Local art dressing. No physics or network ownership changes.

const TEXTURES: String = "res://content/environments/valhalla/textures/KB3D_VHL_"
var storm: ShaderMaterial = ShaderMaterial.new()
var lamps: Array[OmniLight3D] = []
var elapsed: float = 0.0
var storm_light: DirectionalLight3D
var iron: StandardMaterial3D = StandardMaterial3D.new()
var amber: StandardMaterial3D = StandardMaterial3D.new()

func _ready() -> void:
	name = "AshenVillage"
	build.call_deferred()

func build() -> void:
	var village: Node3D = get_parent() as Node3D
	iron.albedo_color = Color("292b29")
	iron.metallic = 0.7
	iron.roughness = 0.72
	amber.albedo_color = Color("e5a756")
	amber.emission_enabled = true
	amber.emission = Color("ffae50")
	amber.emission_energy_multiplier = 2.8
	amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for node: Node in village.find_children("*", "WorldEnvironment", true, false):
		var environment: Environment = (node as WorldEnvironment).environment
		storm.shader = preload("res://content/environments/grim/storm_sky.gdshader")
		storm.set_shader_parameter("panorama", load("res://content/environments/grim/storm_sky.png"))
		var sky: Sky = Sky.new()
		sky.sky_material = storm
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		sky.radiance_size = Sky.RADIANCE_SIZE_64
		environment.sky = sky
		environment.ambient_light_sky_contribution = 0.25
		environment.ambient_light_color = Color("829698")
		environment.fog_light_color = Color("586d73")
		environment.fog_density = 0.009
		environment.fog_height_density = 0.0
		environment.fog_aerial_perspective = 0.35
		environment.fog_sky_affect = 0.2
		environment.fog_sun_scatter = 0.04
	refresh_materials(village)
	for x: float in [-15.0, 15.0]:
		for z: float in [-8.0, 9.0]:
			var y: float = float(village.call("ground_height", x, z))
			lantern(Vector3(x + (1.9 if x < 0 else -1.9), y + 2.28, z + 1.1))
	# Wait for static prop shapes to enter the physics space before placing facade lights.
	await get_tree().physics_frame
	for center: Vector3 in [Vector3(-15,0,-17), Vector3(-4,0,-21), Vector3(13,0,-19), Vector3(19,0,17), Vector3(-7,0,20)]:
		var toward: Vector3 = Vector3(-center.x, 0.0, -center.z).normalized()
		var target: Vector3 = center + Vector3.UP * 1.8
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(target + toward * 9.0, target - toward * 4.0)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"] as Vector3
		if absf(normal.y) > 0.25:
			continue
		var wall: Vector3 = (hit["position"] as Vector3) + normal * 0.045
		window(wall, normal)
		lantern(wall + normal * 0.32 + normal.cross(Vector3.UP) * 1.0)
	storm_light = DirectionalLight3D.new()
	storm_light.name = "DistantRedSheetLightning"
	storm_light.light_color = Color("a12c28")
	storm_light.light_energy = 0.0
	storm_light.rotation_degrees = Vector3(-25, 145, 0)
	storm_light.light_bake_mode = Light3D.BAKE_DISABLED
	add_child(storm_light)
	print("ASHEN_VILLAGE_OK: storm sky, material maps, ", lamps.size(), " practical lights")

func refresh_materials(village: Node3D) -> void:
	var copies: Dictionary[Material, Material] = {}
	for node: Node in village.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node as MeshInstance3D
		if visual.mesh == null:
			continue
		for surface: int in range(visual.mesh.get_surface_count()):
			var source: Material = visual.get_active_material(surface)
			if source == null:
				continue
			if copies.has(source):
				if visual.material_override != null:
					visual.material_override = copies[source]
				else:
					visual.set_surface_override_material(surface, copies[source])
				continue
			var material: Material = source.duplicate() as Material
			if material is StandardMaterial3D:
				var pbr: StandardMaterial3D = material as StandardMaterial3D
				# Keep authored normal/roughness/metal maps, tint only this instance.
				pbr.roughness = maxf(pbr.roughness, 0.82)
				pbr.albedo_color *= Color(0.78, 0.80, 0.77)
			elif material is ShaderMaterial:
				var custom: ShaderMaterial = material as ShaderMaterial
				if custom.get_shader_parameter("grain") != null:
					custom.shader = timber_shader()
					for channel: String in ["basecolor", "normal", "roughness"]:
						custom.set_shader_parameter(channel, load(TEXTURES + "WoodPlanksFlat_" + channel + ".png"))
				elif custom.get_shader_parameter("dye") != null:
					var dye: Vector3 = custom.get_shader_parameter("dye") as Vector3
					custom.set_shader_parameter("dye", dye * Vector3(0.6, 0.55, 0.52))
			copies[source] = material
			if visual.material_override != null:
				visual.material_override = material
			else:
				visual.set_surface_override_material(surface, material)

func timber_shader() -> Shader:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D basecolor : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness : filter_linear_mipmap_anisotropic, repeat_enable;
void fragment(){
 vec2 uv=UV*vec2(0.65,2.0);
 ALBEDO=texture(basecolor,uv).rgb*vec3(0.55,0.59,0.57);
 NORMAL_MAP=texture(normal,uv).rgb;
 NORMAL_MAP_DEPTH=0.4;
 ROUGHNESS=max(0.78,texture(roughness,uv).r);
}
"""
	return shader

func box(size: Vector3, point: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = point
	parent.add_child(visual)
	return visual

func lantern(point: Vector3) -> void:
	var fixture: Node3D = Node3D.new()
	fixture.name = "IronLantern"
	add_child(fixture)
	fixture.global_position = point
	box(Vector3(0.17,0.27,0.17), Vector3.ZERO, amber, fixture)
	for height: float in [-0.17,0.17]:
		box(Vector3(0.27,0.055,0.27), Vector3(0,height,0), iron, fixture)
	for x: float in [-0.11,0.11]:
		for z: float in [-0.11,0.11]:
			box(Vector3(0.025,0.32,0.025), Vector3(x,0,z), iron, fixture)
	box(Vector3(0.035,0.22,0.035), Vector3(0,0.28,0), iron, fixture)
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color("ffb465")
	light.light_energy = 1.7
	light.omni_range = 4.8
	light.omni_attenuation = 1.35
	light.light_bake_mode = Light3D.BAKE_DISABLED
	# Small non-shadowing pool keeps Mobile's light cost bounded.
	fixture.add_child(light)
	lamps.append(light)

func window(point: Vector3, normal: Vector3) -> void:
	var frame: Node3D = Node3D.new()
	frame.name = "WarmWindow"
	add_child(frame)
	frame.global_position = point
	frame.look_at(point + normal)
	box(Vector3(0.65,0.85,0.035), Vector3.ZERO, amber, frame)
	for x: float in [-0.34,0.0,0.34]:
		box(Vector3(0.055,0.95,0.065), Vector3(x,0,-0.03), iron, frame)
	for y: float in [-0.45,0.0,0.45]:
		box(Vector3(0.73,0.055,0.065), Vector3(0,y,-0.03), iron, frame)

func _process(delta: float) -> void:
	elapsed += delta
	for index: int in range(lamps.size()):
		lamps[index].light_energy = 1.7 + sin(elapsed * 3.1 + float(index)*2.7)*0.08
	# Two soft pulses every 31 seconds, localized inside the storm clouds.
	var phase: float = fmod(elapsed,31.0)
	var flash: float = maxf(0.0,1.0-absf(phase-21.0)/0.3)*0.45 + maxf(0.0,1.0-absf(phase-21.65)/0.2)*0.24
	storm.set_shader_parameter("lightning", flash)
	if storm_light != null:
		storm_light.light_energy = flash * 0.12
