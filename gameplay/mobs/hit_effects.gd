class_name HitEffects
extends RefCounted

# Cosmetic blood for raider hits, run on every peer from the host's hit RPCs. Realistic in look
# (dark, wet, gravity-driven, leaving splatter where it lands), exaggerated in quantity and reach.
# Marks are meshes laid on the surface, not Decals: the Mobile renderer lets only 8 decals touch
# one mesh, and the terrain is one mesh, so most of a bisect's splatter would never show.
const MAX_STAINS: int = 96
const STAIN_LIFE: float = 25.0
const RAY_TRIES: int = 3
# The one blood colour: drops, mist, splatter, wounds (mob_overlay.gdshader) and cut flesh
# (mob_cut.gdshader) all use this value so blood reads the same in every interaction.
const BLOOD: Color = Color(0.3, 0.012, 0.01)
static var stain_materials: Array[ShaderMaterial] = []
static var stain_shader: Shader
static var stains: Array[MeshInstance3D] = []
static var materials: Dictionary[String, StandardMaterial3D] = {}
# Splatter on a surface: the texture's alpha, wet where thick. `spread` grows a pool from its
# centre, `fade` dims it out; both per mark.
const STAIN_SHADER: String = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : filter_linear_mipmap, repeat_disable;
instance uniform float spread = 1.0;
instance uniform float fade = 1.0;
void fragment() {
	vec2 uv = (UV - 0.5) / max(spread, 0.01) + 0.5;
	vec4 color = texture(albedo_tex, uv);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	ALBEDO = color.rgb;
	ALPHA = color.a * inside * fade;
	// Wet but not a mirror: a sharper gloss turns the pools white or sky-grey at low angles.
	ROUGHNESS = max(texture(orm_tex, uv).g, 0.5);
	SPECULAR = 0.15;
}
"""

static func enabled(scene: Node) -> bool:
	return scene != null and DisplayServer.get_name() != "headless"

# A damaging cut: spray thrown within the blade's plane along its travel, a sheet sprayed off
# the length of the gash, a fine mist, and splatter wherever the spray lands.
static func slash(scene: Node, point: Vector3, normal: Vector3, travel: Vector3, outward: Vector3, amount: float) -> void:
	if not enabled(scene):
		return
	var along: Vector3 = in_plane(travel, normal)
	var root: Node3D = holder(scene, point, 2.2)
	for step: int in range(-2, 3):
		var direction: Vector3 = (along.rotated(normal, deg_to_rad(step * 14.0)) + Vector3.UP * 0.15).normalized()
		root.add_child(drops(direction, int(9.0 * amount), 2.0 + amount, 4.0 + 2.5 * amount, 0.012, 0.035, 8.0))
	# Heavier globs that fall short, and a thin back-spray against the travel.
	root.add_child(drops((along + Vector3.UP * 0.35).normalized(), int(4.0 * amount), 1.0, 2.5 + amount, 0.03, 0.06, 25.0, 0.9))
	root.add_child(drops((-along + Vector3.UP * 0.5).normalized(), int(4.0 * amount), 0.8, 2.0, 0.008, 0.02, 30.0))
	root.add_child(sheet(along, normal, outward, amount))
	root.add_child(trail(along, normal, amount))
	root.add_child(mist(along, amount))
	var exclude: Array[RID] = actor_rids(scene)
	for index: int in range(int(2.0 + amount * 1.5)):
		var reach: float = randf_range(0.8, 2.2) * amount
		var direction: Vector3 = along.rotated(normal, randf_range(-0.5, 0.5)) * reach + Vector3.DOWN * 2.2
		splat(scene, point, direction, along, randf_range(0.8, 1.3) * sqrt(amount), exclude)
	# The pool under the raider keeps spreading for a couple of seconds.
	splat(scene, point, Vector3.DOWN * 2.5, along, 1.4 * sqrt(amount), exclude, 2.5)

# A bisect on top of the slash: both cut faces burst along the plane's normal, a ring of spray
# flies out within the plane, heavy globs slop down, and splatter lands all around.
static func sever(scene: Node, point: Vector3, normal: Vector3, travel: Vector3) -> void:
	if not enabled(scene):
		return
	var along: Vector3 = in_plane(travel, normal)
	var root: Node3D = holder(scene, point, 2.6)
	for face: float in [1.0, -1.0]:
		root.add_child(drops((normal * face + Vector3.UP * 0.3).normalized(), 64, 1.5, 5.5, 0.012, 0.04, 35.0, 1.3))
		root.add_child(drops((normal * face * 0.4 + Vector3.UP).normalized(), 40, 0.8, 3.0, 0.03, 0.07, 30.0, 1.2))
	for step: int in range(8):
		var direction: Vector3 = (along.rotated(normal, TAU * step / 8.0) + Vector3.UP * 0.25).normalized()
		root.add_child(drops(direction, 40, 2.0, 6.5, 0.01, 0.03, 12.0))
	root.add_child(mist(along, 3.0))
	root.add_child(mist(-along, 2.0))
	var exclude: Array[RID] = actor_rids(scene)
	for index: int in range(12):
		var direction: Vector3 = along.rotated(normal, TAU * index / 12.0 + randf_range(-0.2, 0.2)) * randf_range(0.8, 3.2)
		direction += normal * randf_range(-1.2, 1.2) + Vector3.DOWN * 2.4
		splat(scene, point, direction, direction, randf_range(0.9, 1.6), exclude)

# A bisected half bleeding out: a heavy pulsing stream from the cut face that leaves a trail of
# splatter under it as the half tumbles, then a wide pool spreading where it comes to rest.
static func spill(part: Node3D, local_point: Vector3, local_direction: Vector3, duration: float = 3.5) -> void:
	if not enabled(part):
		return
	var direction: Vector3 = local_direction.normalized()
	for stream: GPUParticles3D in [
			drops(direction, 64, 1.0, 3.2, 0.016, 0.04, 14.0, 1.2),
			drops(direction, 40, 0.4, 1.6, 0.03, 0.06, 30.0, 1.0)]:
		stream.one_shot = false
		stream.explosiveness = 0.0
		stream.randomness = 0.6
		stream.local_coords = false
		stream.position = local_point
		part.add_child(stream)
		part.get_tree().create_timer(duration).timeout.connect(func() -> void:
			if is_instance_valid(stream):
				stream.emitting = false)
	var scene: Node = part.get_tree().current_scene
	var exclude: Array[RID] = actor_rids(scene)
	var ticks: int = int(duration / 0.3)
	for tick: int in range(ticks):
		part.get_tree().create_timer(0.15 + tick * 0.3).timeout.connect(func() -> void:
			if not is_instance_valid(part) or not is_instance_valid(scene):
				return
			var from: Vector3 = part.to_global(local_point)
			var flow: Vector3 = part.global_basis * direction
			var spray: Vector3 = Vector3(flow.x, 0.0, flow.z) * randf_range(0.2, 0.9) + Vector3.DOWN * 3.0
			# The stream thins as the half empties.
			splat(scene, from, spray, flow, lerpf(1.1, 0.5, float(tick) / ticks) * randf_range(0.8, 1.2), exclude))
	part.get_tree().create_timer(duration * 0.6).timeout.connect(func() -> void:
		if is_instance_valid(part) and is_instance_valid(scene):
			splat(scene, part.to_global(local_point), Vector3.DOWN * 3.0, part.global_basis * direction, 2.6, exclude, duration))

# A light contact without damage: a few drops and at most a small mark below.
static func splash(scene: Node, point: Vector3, direction: Vector3, amount: float) -> void:
	if not enabled(scene):
		return
	var root: Node3D = holder(scene, point, 1.6)
	root.add_child(drops((direction + Vector3.UP * 0.5).normalized(), int(10.0 * amount), 1.0, 1.5 + 2.5 * amount, 0.01, 0.03, 35.0))
	if amount > 0.5:
		splat(scene, point, direction * 0.6 + Vector3.DOWN * 2.2, direction, 0.5, actor_rids(scene))

# A pulsing stream from a severed body, attached to the moving part (for bisect halves).
static func gush(part: Node3D, local_point: Vector3, local_direction: Vector3, duration: float = 1.4) -> void:
	if not enabled(part):
		return
	var stream: GPUParticles3D = drops(local_direction.normalized(), 36, 1.2, 3.0, 0.012, 0.03, 12.0, 1.2)
	stream.one_shot = false
	stream.explosiveness = 0.0
	stream.randomness = 0.6
	stream.local_coords = false
	stream.position = local_point
	part.add_child(stream)
	part.get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(stream):
			stream.emitting = false)

static func in_plane(travel: Vector3, normal: Vector3) -> Vector3:
	var along: Vector3 = travel - normal * travel.dot(normal)
	if along.length_squared() < 0.0001:
		along = normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT)
	return along.normalized()

static func holder(scene: Node, point: Vector3, life: float) -> Node3D:
	var root: Node3D = Node3D.new()
	root.position = point
	scene.add_child(root)
	scene.get_tree().create_timer(life).timeout.connect(root.queue_free)
	return root

static func blood(kind: String) -> StandardMaterial3D:
	if materials.has(kind):
		return materials[kind]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# Wet blood: deep red, glossy, a hint of clearcoat for the bright specular pinpoints.
	material.albedo_color = BLOOD
	material.roughness = 0.12 if kind == "drop" else 0.35
	material.metallic_specular = 0.7
	material.clearcoat_enabled = kind == "drop"
	material.clearcoat_roughness = 0.05
	materials[kind] = material
	return material

static func drops(direction: Vector3, count: int, speed_min: float, speed_max: float, size_min: float, size_max: float, spread: float, lifetime: float = 1.1) -> GPUParticles3D:
	var burst: GPUParticles3D = GPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.randomness = 0.3
	burst.amount = clampi(count, 2, 64)
	burst.lifetime = lifetime
	burst.emitting = true
	burst.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = direction
	process.spread = spread
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.gravity = Vector3(0, -9.8, 0)
	process.damping_min = 0.1
	process.damping_max = 0.6
	process.scale_min = size_min
	process.scale_max = size_max
	# Drops stretch along their flight while fast and round up as they slow.
	process.particle_flag_align_y = true
	var stretch: Curve = Curve.new()
	stretch.add_point(Vector2(0.0, 1.0))
	stretch.add_point(Vector2(0.4, 0.75))
	stretch.add_point(Vector2(1.0, 0.45))
	var scale_curve: CurveTexture = CurveTexture.new()
	scale_curve.curve = stretch
	process.scale_curve = scale_curve
	burst.process_material = process
	var drop: CapsuleMesh = CapsuleMesh.new()
	drop.radius = 0.5
	drop.height = 2.4
	drop.radial_segments = 8
	drop.rings = 2
	drop.material = blood("drop")
	burst.draw_pass_1 = drop
	return burst

# Blood sprayed off the whole length of the gash, outward from the body, in the cut's plane.
static func sheet(along: Vector3, normal: Vector3, outward: Vector3, amount: float) -> GPUParticles3D:
	var side: Vector3 = normal.cross(along).normalized()
	var away: Vector3 = outward - normal * outward.dot(normal)
	away = away.normalized() if away.length_squared() > 0.0001 else side
	var burst: GPUParticles3D = drops(Vector3.ZERO, int(24.0 * amount), 1.2, 3.0 + amount, 0.008, 0.022, 18.0, 0.8)
	# The emitter's frame: x along the gash, y the plane normal, so the box lies in the plane.
	burst.basis = Basis(along, normal, along.cross(normal)).orthonormalized()
	var process: ParticleProcessMaterial = burst.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.3, 0.004, 0.02)
	process.direction = (burst.basis.inverse() * (away + along * 0.8)).normalized()
	burst.explosiveness = 0.75
	return burst

# Drops flung off the blade along the rest of the swing: a trail of blood, not a glowing arc.
static func trail(along: Vector3, normal: Vector3, amount: float) -> GPUParticles3D:
	var burst: GPUParticles3D = drops(Vector3.ZERO, int(30.0 * amount), 2.5, 5.0 + 2.0 * amount, 0.01, 0.03, 6.0, 1.0)
	burst.basis = Basis(along, normal, along.cross(normal)).orthonormalized()
	var process: ParticleProcessMaterial = burst.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.45 * amount, 0.01, 0.01)
	process.emission_shape_offset = Vector3(0.45 * amount, 0.0, 0.0) # from the cut onward
	process.direction = Vector3(1, 0, 0)
	burst.explosiveness = 0.8
	return burst

static func mist(along: Vector3, amount: float) -> GPUParticles3D:
	var burst: GPUParticles3D = GPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = int(40.0 * amount)
	burst.lifetime = 0.5
	burst.emitting = true
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = along
	process.spread = 70.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 3.5 * amount
	process.damping_min = 6.0
	process.damping_max = 10.0
	process.gravity = Vector3(0, -1.5, 0)
	process.scale_min = 0.006
	process.scale_max = 0.016
	burst.process_material = process
	var dot: SphereMesh = SphereMesh.new()
	dot.radius = 0.5
	dot.height = 1.0
	dot.radial_segments = 4
	dot.rings = 2
	dot.material = blood("mist")
	burst.draw_pass_1 = dot
	return burst

static func actor_rids(scene: Node) -> Array[RID]:
	var rids: Array[RID] = []
	for node: Node in scene.get_tree().get_nodes_in_group("hostile_mobs"):
		rids.append((node as CollisionObject3D).get_rid())
	return rids

# Throw a ray along the spray's path and leave a directional splatter where it lands.
static func splat(scene: Node, from: Vector3, offset: Vector3, travel: Vector3, size: float, exclude: Array[RID], spread_time: float = 0.0) -> void:
	var world: World3D = (scene as Node3D).get_world_3d() if scene is Node3D else scene.get_viewport().world_3d
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + offset)
	query.exclude = exclude.duplicate()
	var hit: Dictionary = {}
	for attempt: int in range(RAY_TRIES):
		hit = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return
		# Bodies that move would leave the mark floating; only static ground and walls take it.
		if hit["collider"] is StaticBody3D or hit["collider"] is CSGShape3D:
			break
		query.exclude.append(hit["rid"] as RID)
		hit = {}
	if hit.is_empty():
		return
	# Marks appear when the spray would arrive, not at the moment of the cut.
	var flight: float = clampf(sqrt(2.0 * maxf(0.0, from.y - (hit["position"] as Vector3).y) / 9.8), 0.12, 0.6)
	var position: Vector3 = hit["position"] as Vector3
	var surface: Vector3 = hit["normal"] as Vector3
	scene.get_tree().create_timer(flight).timeout.connect(func() -> void:
		if is_instance_valid(scene):
			place_stain(scene, position, surface, travel, size, spread_time))

static func place_stain(scene: Node, position: Vector3, normal: Vector3, travel: Vector3, size: float, spread_time: float = 0.0) -> void:
	if stain_materials.size() < 4:
		make_splatter(stain_materials.size())
	# Long axis along the spray's travel over the surface: drops trail away from the hit.
	var forward: Vector3 = travel - normal * travel.dot(normal)
	forward = forward.normalized() if forward.length_squared() > 0.0001 else normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var right: Vector3 = forward.cross(normal).normalized()
	var frame: Transform3D = Transform3D(Basis(right, normal, -forward).orthonormalized(), position)
	var stain: MeshInstance3D = MeshInstance3D.new()
	stain.mesh = stain_mesh(scene, frame, Vector2(size, size * 1.6))
	stain.material_override = stain_materials[randi() % stain_materials.size()]
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(stain)
	stain.global_transform = frame
	stains.append(stain)
	while stains.size() > MAX_STAINS:
		var old: MeshInstance3D = stains.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	if spread_time > 0.0:
		stain.set_instance_shader_parameter("spread", 0.35)
		stain.create_tween().tween_method(func(value: float) -> void: stain.set_instance_shader_parameter("spread", value), 0.35, 1.0, spread_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var tween: Tween = stain.create_tween()
	tween.tween_interval(STAIN_LIFE)
	tween.tween_method(func(value: float) -> void: stain.set_instance_shader_parameter("fade", value), 1.0, 0.0, 4.0)
	tween.tween_callback(stain.queue_free)

# A sheet over the surface in the mark's frame (y along the surface normal). Small marks are flat;
# a large one drapes over bumps, each grid point dropped onto static ground by a ray.
static func stain_mesh(scene: Node, frame: Transform3D, extent: Vector2) -> ArrayMesh:
	var cells: int = 1 if extent.x < 1.2 else 6
	var space: PhysicsDirectSpaceState3D = (scene as Node3D).get_world_3d().direct_space_state if scene is Node3D else scene.get_viewport().world_3d.direct_space_state
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for row: int in range(cells + 1):
		for column: int in range(cells + 1):
			var uv: Vector2 = Vector2(float(column) / cells, float(row) / cells)
			var local: Vector3 = Vector3((uv.x - 0.5) * extent.x, 0.0, (uv.y - 0.5) * extent.y)
			if cells > 1:
				var top: Vector3 = frame * (local + Vector3.UP * 0.4)
				var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top - frame.basis.y * 0.8))
				if not hit.is_empty() and (hit["collider"] is StaticBody3D or hit["collider"] is CSGShape3D):
					local.y = (frame.affine_inverse() * (hit["position"] as Vector3)).y
			# Lifted off the surface, a little more for each newer mark so overlaps do not flicker.
			local.y += 0.01 + 0.0005 * (stains.size() % 12)
			vertices.append(local)
			uvs.append(uv)
			normals.append(Vector3.UP)
	var indices: PackedInt32Array = PackedInt32Array()
	for row: int in range(cells):
		for column: int in range(cells):
			var corner: int = row * (cells + 1) + column
			indices.append_array([corner, corner + 1, corner + cells + 1, corner + 1, corner + cells + 2, corner + cells + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# Procedural splatter, splashed along -v (texture "up" maps to the mark's forward): a dense
# pool at the impact, satellite drops and elongated streaks flung ahead, all with soft wet edges.
static func make_splatter(seed_value: int) -> void:
	var size: int = 128
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7919 * (seed_value + 1)
	var alpha: PackedFloat32Array = PackedFloat32Array()
	alpha.resize(size * size)
	var blobs: Array[Vector4] = [] # x, y, radius, stretch along y
	var core: Vector2 = Vector2(size * 0.5, size * 0.72)
	for index: int in range(7):
		blobs.append(Vector4(core.x + rng.randf_range(-9, 9), core.y + rng.randf_range(-7, 7), rng.randf_range(7, 14), 1.0))
	for index: int in range(18):
		var distance: float = rng.randf_range(16, 64)
		var angle: float = rng.randf_range(-0.55, 0.55)
		blobs.append(Vector4(core.x + sin(angle) * distance, core.y - cos(angle) * distance, rng.randf_range(1.0, 4.0) * (1.0 - distance / 90.0), rng.randf_range(1.0, 2.6)))
	for index: int in range(10):
		blobs.append(Vector4(core.x + rng.randf_range(-40, 40), core.y + rng.randf_range(-30, 20), rng.randf_range(0.7, 1.6), 1.0))
	for blob: Vector4 in blobs:
		var reach: int = int(ceil(blob.z * blob.w)) + 2
		for y: int in range(maxi(0, int(blob.y) - reach), mini(size, int(blob.y) + reach + 1)):
			for x: int in range(maxi(0, int(blob.x) - reach), mini(size, int(blob.x) + reach + 1)):
				var d: float = Vector2((x - blob.x) / blob.z, (y - blob.y) / (blob.z * blob.w)).length()
				var value: float = clampf((1.0 - d) * blob.z * 0.9, 0.0, 1.0)
				alpha[y * size + x] = maxf(alpha[y * size + x], value)
	var albedo: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var orm: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var a: float = alpha[y * size + x]
			# Thick blood is darker; thin edges show more red.
			var shade: float = lerpf(1.15, 0.7, a)
			albedo.set_pixel(x, y, Color(BLOOD.r * shade, BLOOD.g * shade, BLOOD.b * shade, a))
			orm.set_pixel(x, y, Color(1.0, lerpf(0.45, 0.2, a), 0.0, a))
	albedo.generate_mipmaps()
	orm.generate_mipmaps()
	if stain_shader == null:
		stain_shader = Shader.new()
		stain_shader.code = STAIN_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = stain_shader
	material.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(albedo))
	material.set_shader_parameter("orm_tex", ImageTexture.create_from_image(orm))
	stain_materials.append(material)
