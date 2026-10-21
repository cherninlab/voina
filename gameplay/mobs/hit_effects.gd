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
static var pool_materials: Array[ShaderMaterial] = []
static var stain_shader: Shader
static var stains: Array[MeshInstance3D] = []
static var pools: Array[MeshInstance3D] = []
static var materials: Dictionary[String, StandardMaterial3D] = {}
# Where a splatter texture's impact sits (its dense core); drops fly toward v = 0 from there.
const SPLATTER_CORE: Vector2 = Vector2(0.5, 0.72)
# A pool's mesh is this many times its size: room to keep spreading when more blood joins it.
const POOL_ROOM: float = 1.2
const POOL_START: float = 0.72
# Liquid on a surface. The texture holds thickness; the liquid ends with a crisp edge where it
# drops below a level, and `spread` lowers that level so a pool floods outward along its own
# shape from the thickest spot. Where the liquid is deep its surface is a flat mirror; toward the
# edge it is only a film over uneven ground, so the surface takes on the ground's small bumps and
# the reflection breaks up there. It reflects the scene where a short screen-space march finds
# it, the sky elsewhere, and the sun as a small glint. Each fragment also checks the scene depth behind it, so
# a mark running past the edge of a box or ledge is cut off there instead of hanging in the air.
# `dry` dulls and darkens it over the mark's life, `fade` dims it out.
const STAIN_SHADER: String = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D field_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 blood : source_color;
instance uniform float spread = 1.0;
instance uniform float fade = 1.0;
instance uniform float dry = 0.0;
varying float fresnel;

vec3 scene_view(vec2 uv, mat4 inverse_projection) {
	vec4 view = inverse_projection * vec4(uv * 2.0 - 1.0, texture(depth_tex, uv).r, 1.0);
	return view.xyz / view.w;
}

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 at) {
	vec2 cell = floor(at);
	vec2 t = fract(at);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), t.x), mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), t.x), t.y);
}

// Ground relief under the film, in metres of height per metre: grit over gentle lumps.
float relief(vec2 at) {
	return noise(at * 9.0) * 0.6 + noise(at * 31.0) * 0.3 + noise(at * 83.0) * 0.1;
}

vec2 screen(vec3 view, mat4 projection) {
	vec4 clip = projection * vec4(view, 1.0);
	return clip.xy / clip.w * 0.5 + 0.5;
}

// Drawn a few centimetres nearer the camera along its own view ray: same place on screen, but it
// wins the depth test against ground overlays laid just above the collision it was placed on
// (church yard earth, torch-road mud, bog pools: 3-3.5 cm).
void vertex() {
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(view * max(0.0, 1.0 - 0.05 / max(length(view), 0.001)), 1.0);
}

void fragment() {
	// Nothing solid right behind this fragment: the mark ran off an edge into the air.
	vec3 behind = scene_view(SCREEN_UV, INV_PROJECTION_MATRIX);
	if (VERTEX.z - behind.z > 0.04 + 0.004 * -VERTEX.z) {
		discard;
	}
	float thick = texture(field_tex, UV).r;
	float level = mix(0.95, 0.06, clamp(spread, 0.0, 1.0));
	float soft = max(fwidth(thick), 0.004);
	// 1 at the edge, 0 where the liquid is deep enough to lie flat.
	float shallow = 1.0 - smoothstep(level, level + 0.22, thick);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 up = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 flat_at = world.xz;
	float e = 0.004;
	vec2 slope = vec2(relief(flat_at + vec2(e, 0.0)) - relief(flat_at), relief(flat_at + vec2(0.0, e)) - relief(flat_at)) / e;
	up = normalize(up - vec3(slope.x, 0.0, slope.y) * 0.035 * shallow * shallow);
	NORMAL = normalize((VIEW_MATRIX * vec4(up, 0.0)).xyz);
	vec3 view = normalize(-VERTEX);
	fresnel = 0.03 + 0.97 * pow(1.0 - clamp(dot(NORMAL, view), 0.0, 1.0), 5.0);
	// Reflection: march the mirrored view ray through the depth buffer. The first step that goes
	// behind the scene is refined by bisection to the surface it crossed, and the march stops
	// there, so each object is reflected once, in one place.
	vec3 ray = reflect(-view, NORMAL);
	vec3 at = VERTEX + NORMAL * 0.01;
	vec3 last = at;
	float stride = 0.04 + 0.008 * -VERTEX.z;
	float found = 0.0;
	vec3 mirrored = vec3(0.0);
	for (int index = 0; index < 28; index++) {
		last = at;
		at += ray * stride;
		stride *= 1.15;
		if (at.z > -0.05) {
			break;
		}
		vec2 uv = screen(at, PROJECTION_MATRIX);
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		if (scene_view(uv, INV_PROJECTION_MATRIX).z > at.z) {
			for (int step = 0; step < 6; step++) {
				vec3 middle = (last + at) * 0.5;
				if (scene_view(screen(middle, PROJECTION_MATRIX), INV_PROJECTION_MATRIX).z > middle.z) {
					at = middle;
				} else {
					last = middle;
				}
			}
			uv = screen(at, PROJECTION_MATRIX);
			// Only a surface the ray really reached, not one far in front of it.
			if (scene_view(uv, INV_PROJECTION_MATRIX).z - at.z < 0.04 + 0.01 * -at.z) {
				vec2 border = min(uv, 1.0 - uv);
				found = clamp(min(border.x, border.y) * 12.0, 0.0, 1.0) * (1.0 - smoothstep(4.0, 9.0, distance(at, VERTEX)));
				mirrored = textureLod(screen_tex, uv, 0.0).rgb;
			}
			break;
		}
	}
	float wet = 1.0 - dry;
	ALBEDO = blood * mix(0.5, 0.65, dry);
	ALPHA = smoothstep(level - soft, level + soft, thick) * fade;
	ROUGHNESS = mix(mix(0.04, 0.12, shallow), 0.6, dry);
	// Where the scene is reflected it replaces the sky reflection the renderer would add.
	SPECULAR = 0.5 * (1.0 - found * wet);
	EMISSION = mirrored * found * fresnel * wet;
}

// Direct light: plain diffuse, and the sun as a small sharp glint, as on a still liquid surface,
// instead of the renderer's broad highlight that blows the whole pool out to white.
void light() {
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	float glint = pow(clamp(dot(NORMAL, normalize(VIEW + LIGHT)), 0.0, 1.0), mix(20000.0, 60.0, dry));
	SPECULAR_LIGHT += glint * mix(6.0, 0.2, dry) * fresnel * ATTENUATION * LIGHT_COLOR;
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

# A bisected half bleeding out: a heavy pulsing stream from the middle of the cut face that
# splatters under it as the half tumbles, then pools where the stream lands, the pool spreading
# as more blood joins it.
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
			# The stream thins as the half empties. While the half flies it splatters; once it
			# has come down, the stream pools where it lands and keeps feeding that pool.
			var size: float = lerpf(1.1, 0.5, float(tick) / ticks) * randf_range(0.8, 1.2)
			splat(scene, from, spray, flow, size if tick < 2 else size * 1.6, exclude, 0.0 if tick < 2 else 1.5))
	part.get_tree().create_timer(duration * 0.6).timeout.connect(func() -> void:
		if is_instance_valid(part) and is_instance_valid(scene):
			var flow: Vector3 = part.global_basis * direction
			splat(scene, part.to_global(local_point), Vector3(flow.x, 0.0, flow.z) * 0.4 + Vector3.DOWN * 3.0, flow, 2.6, exclude, duration))

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

# The middle of a cut face: where the cut plane crosses the body's axis at the hit's height, not
# the skin the blade touched (which lies off to one side of the face).
static func cut_center(point: Vector3, normal: Vector3, axis: Vector3) -> Vector3:
	var on_axis: Vector3 = Vector3(axis.x, point.y, axis.z)
	return on_axis - normal * normal.dot(on_axis - point)

# The middle of the cut face on one ragdoll part: where the part's own axis (its body Z runs
# along the segment) crosses the plane, so a severed limb bleeds from its own stump.
static func part_face(part: Node3D, center: Vector3, normal: Vector3) -> Vector3:
	var axis: Vector3 = part.global_basis.z.normalized()
	var at: Vector3 = part.global_position
	var across: float = axis.dot(normal)
	if absf(across) > 0.2:
		at += axis * clampf(normal.dot(center - at) / across, -0.4, 0.4)
	return at - normal * normal.dot(at - center)

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
	for index: int in range(pools.size() - 1, -1, -1):
		if not is_instance_valid(pools[index]):
			pools.remove_at(index)
	if spread_time > 0.0:
		place_pool(scene, position, normal, travel, size, spread_time)
		return
	# Drops that fall into a pool join the liquid instead of marking it.
	for pool: MeshInstance3D in pools:
		if position.distance_to(pool.global_position) < 0.9 * pool_radius(pool):
			return
	if stain_materials.size() < 4:
		stain_materials.append(liquid(make_splatter(stain_materials.size())))
	var stain: MeshInstance3D = new_mark(scene, position, normal, travel, Vector2(size, size * 1.6), SPLATTER_CORE, stain_materials[randi() % stain_materials.size()])
	start_life(stain)

# A pool where a stream lands. One landing inside an existing pool feeds it instead, so the
# liquid keeps spreading as one surface rather than stacking edges over itself.
static func place_pool(scene: Node, position: Vector3, normal: Vector3, travel: Vector3, size: float, spread_time: float) -> void:
	for pool: MeshInstance3D in pools:
		if position.distance_to(pool.global_position) < pool_radius(pool) + 0.25 * size:
			var extent: float = float(pool.get_meta("extent"))
			if size * POOL_ROOM > extent:
				# A bigger flow than the pool was made for: a larger sheet, at a lower level so
				# the liquid already there keeps its reach.
				var reach: float = (1.0 - lerpf(0.95, 0.06, float(pool.get_meta("spread")))) * extent
				extent = size * POOL_ROOM
				pool.mesh = stain_mesh(scene, pool.global_transform, Vector2(extent, extent), Vector2(0.5, 0.5))
				pool.set_meta("extent", extent)
				var spread: float = (0.95 - (1.0 - reach / extent)) / 0.89
				pool.set_meta("spread", spread)
				pool.set_instance_shader_parameter("spread", spread)
				pool.set_meta("target", spread)
			grow(pool, minf(1.0, maxf(float(pool.get_meta("target")), POOL_START * 0.8) + 0.25 * minf(1.0, size / extent)), spread_time)
			start_life(pool)
			absorb(pool, spread_time)
			return
	if pool_materials.size() < 3:
		pool_materials.append(liquid(make_pool(pool_materials.size())))
	var extent: float = size * POOL_ROOM
	var pool: MeshInstance3D = new_mark(scene, position, normal, travel, Vector2(extent, extent), Vector2(0.5, 0.5), pool_materials[randi() % pool_materials.size()])
	pool.set_meta("extent", extent)
	pool.set_meta("spread", 0.0)
	pool.set_meta("target", 0.0)
	pools.append(pool)
	grow(pool, POOL_START, spread_time)
	start_life(pool)
	absorb(pool, spread_time)

# Once a pool has spread, splatter it covers is part of the liquid: drop those marks so their
# edges do not show through as rings.
static func absorb(pool: MeshInstance3D, delay: float) -> void:
	pool.get_tree().create_timer(delay).timeout.connect(func() -> void:
		if not is_instance_valid(pool):
			return
		var reach: float = 0.95 * pool_radius(pool)
		for stain: MeshInstance3D in stains:
			if is_instance_valid(stain) and stain != pool and not pools.has(stain) and stain.global_position.distance_to(pool.global_position) < reach:
				stain.queue_free())

# Roughly how far a pool reaches now: its texture's mean radius at the current level.
static func pool_radius(pool: MeshInstance3D) -> float:
	return 0.3 * (1.0 - lerpf(0.95, 0.06, float(pool.get_meta("spread")))) * float(pool.get_meta("extent"))

static func grow(pool: MeshInstance3D, target: float, time: float) -> void:
	var from: float = float(pool.get_meta("spread"))
	pool.set_meta("target", target)
	if pool.has_meta("growth"):
		(pool.get_meta("growth") as Tween).kill()
	var tween: Tween = pool.create_tween()
	tween.tween_method(func(value: float) -> void:
		pool.set_meta("spread", value)
		pool.set_instance_shader_parameter("spread", value), from, target, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	pool.set_meta("growth", tween)

# Wet for its life while drying, then fades out and frees itself. Fresh blood rewets a mark.
static func start_life(stain: MeshInstance3D) -> void:
	if stain.has_meta("life"):
		(stain.get_meta("life") as Tween).kill()
	stain.set_instance_shader_parameter("dry", 0.0)
	stain.set_instance_shader_parameter("fade", 1.0)
	var tween: Tween = stain.create_tween()
	tween.tween_method(func(value: float) -> void: stain.set_instance_shader_parameter("dry", value), 0.0, 1.0, STAIN_LIFE).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(func(value: float) -> void: stain.set_instance_shader_parameter("fade", value), 1.0, 0.0, 4.0)
	tween.tween_callback(stain.queue_free)
	stain.set_meta("life", tween)

# A mark lying on the surface, its texture's `pivot` on the hit and its texture "up" along the
# travel over the surface, so drops trail away from where the blood landed.
static func new_mark(scene: Node, position: Vector3, normal: Vector3, travel: Vector3, extent: Vector2, pivot: Vector2, material: ShaderMaterial) -> MeshInstance3D:
	var forward: Vector3 = travel - normal * travel.dot(normal)
	forward = forward.normalized() if forward.length_squared() > 0.0001 else normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var right: Vector3 = forward.cross(normal).normalized()
	var frame: Transform3D = Transform3D(Basis(right, normal, -forward).orthonormalized(), position)
	var stain: MeshInstance3D = MeshInstance3D.new()
	stain.mesh = stain_mesh(scene, frame, extent, pivot)
	stain.material_override = material
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(stain)
	stain.global_transform = frame
	# Stains free themselves after their life (and with the scene): drop those first, so the cap
	# counts live marks and a freed one is never assigned to a typed variable.
	for index: int in range(stains.size() - 1, -1, -1):
		if not is_instance_valid(stains[index]):
			stains.remove_at(index)
	stains.append(stain)
	while stains.size() > MAX_STAINS:
		stains.pop_front().queue_free()
	return stain

# A sheet over the surface in the mark's frame (y along the surface normal), `pivot` (in UV) at
# the origin. Small marks are flat; a large one drapes over bumps, each grid point dropped onto
# static ground by a ray.
static func stain_mesh(scene: Node, frame: Transform3D, extent: Vector2, pivot: Vector2) -> ArrayMesh:
	var cells: int = 1 if extent.x < 1.2 else 6
	var space: PhysicsDirectSpaceState3D = (scene as Node3D).get_world_3d().direct_space_state if scene is Node3D else scene.get_viewport().world_3d.direct_space_state
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for row: int in range(cells + 1):
		for column: int in range(cells + 1):
			var uv: Vector2 = Vector2(float(column) / cells, float(row) / cells)
			var local: Vector3 = Vector3((uv.x - pivot.x) * extent.x, 0.0, (uv.y - pivot.y) * extent.y)
			if cells > 1:
				var top: Vector3 = frame * (local + Vector3.UP * 0.4)
				var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top - frame.basis.y * 0.8))
				if not hit.is_empty() and (hit["collider"] is StaticBody3D or hit["collider"] is CSGShape3D):
					# Follow bumps and dips, but never climb onto an object: the liquid runs under
					# it and the shader cuts what would hang off the top.
					local.y = minf((frame.affine_inverse() * (hit["position"] as Vector3)).y, 0.12)
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

static func liquid(field: Image) -> ShaderMaterial:
	if stain_shader == null:
		stain_shader = Shader.new()
		stain_shader.code = STAIN_SHADER
	field.generate_mipmaps()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = stain_shader
	material.set_shader_parameter("field_tex", ImageTexture.create_from_image(field))
	material.set_shader_parameter("blood", Color(BLOOD.r, BLOOD.g, BLOOD.b))
	return material

# Procedural splatter thickness, splashed along -v (texture "up" maps to the mark's forward): a
# dense pool at SPLATTER_CORE, satellite drops and elongated streaks flung ahead.
static func make_splatter(seed_value: int) -> Image:
	var size: int = 128
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7919 * (seed_value + 1)
	var thickness: PackedFloat32Array = PackedFloat32Array()
	thickness.resize(size * size)
	var blobs: Array[Vector4] = [] # x, y, radius, stretch along y
	var core: Vector2 = SPLATTER_CORE * size
	for index: int in range(7):
		blobs.append(Vector4(core.x + rng.randf_range(-9, 9), core.y + rng.randf_range(-7, 7), rng.randf_range(7, 14), 1.0))
	for index: int in range(18):
		var distance: float = rng.randf_range(16, 64)
		var angle: float = rng.randf_range(-0.55, 0.55)
		blobs.append(Vector4(core.x + sin(angle) * distance, core.y - cos(angle) * distance, rng.randf_range(1.2, 4.0) * (1.0 - distance / 90.0), rng.randf_range(1.0, 2.6)))
	for index: int in range(10):
		blobs.append(Vector4(core.x + rng.randf_range(-40, 40), core.y + rng.randf_range(-30, 20), rng.randf_range(0.9, 1.8), 1.0))
	for blob: Vector4 in blobs:
		var reach: int = int(ceil(blob.z * blob.w)) + 2
		for y: int in range(maxi(0, int(blob.y) - reach), mini(size, int(blob.y) + reach + 1)):
			for x: int in range(maxi(0, int(blob.x) - reach), mini(size, int(blob.x) + reach + 1)):
				var d: float = Vector2((x - blob.x) / blob.z, (y - blob.y) / (blob.z * blob.w)).length()
				# Thickest mid-blob; overlapping blobs merge into one liquid surface.
				thickness[y * size + x] = maxf(thickness[y * size + x], clampf((1.0 - d) * 2.0, 0.0, 1.0))
	return field_image(thickness, size)

# Procedural pool thickness: deepest at the centre, thinning to an irregular lobed rim with a few
# beads of liquid just beyond it, the way blood spreads over uneven ground.
static func make_pool(seed_value: int) -> Image:
	var size: int = 128
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 104729 * (seed_value + 1)
	var phases: Vector3 = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	var grid: int = 9
	var bumps: PackedFloat32Array = PackedFloat32Array()
	for index: int in range(grid * grid):
		bumps.append(rng.randf_range(-1.0, 1.0))
	var beads: Array[Vector3] = [] # x, y, radius in UV
	for index: int in range(7):
		var angle: float = rng.randf() * TAU
		var distance: float = minf(rng.randf_range(0.34, 0.42), 0.45)
		beads.append(Vector3(0.5 + cos(angle) * distance, 0.5 + sin(angle) * distance, rng.randf_range(0.012, 0.03)))
	var thickness: PackedFloat32Array = PackedFloat32Array()
	thickness.resize(size * size)
	for y: int in range(size):
		for x: int in range(size):
			var uv: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / size
			var offset: Vector2 = uv - Vector2(0.5, 0.5)
			var angle: float = atan2(offset.y, offset.x)
			var rim: float = 0.3 * (1.0 + 0.16 * sin(3.0 * angle + phases.x) + 0.08 * sin(5.0 * angle + phases.y) + 0.04 * sin(9.0 * angle + phases.z))
			# Bilinear value noise: the ground's small dips the liquid runs into first.
			var cell: Vector2 = uv * (grid - 1)
			var corner: Vector2i = Vector2i(mini(int(cell.x), grid - 2), mini(int(cell.y), grid - 2))
			var t: Vector2 = (cell - Vector2(corner)) * (cell - Vector2(corner)) * (Vector2(3, 3) - 2.0 * (cell - Vector2(corner)))
			var top: float = lerpf(bumps[corner.y * grid + corner.x], bumps[corner.y * grid + corner.x + 1], t.x)
			var bottom: float = lerpf(bumps[(corner.y + 1) * grid + corner.x], bumps[(corner.y + 1) * grid + corner.x + 1], t.x)
			var value: float = 1.0 - offset.length() / rim + 0.12 * lerpf(top, bottom, t.y)
			for bead: Vector3 in beads:
				value = maxf(value, 0.5 * (1.0 - Vector2(uv.x - bead.x, uv.y - bead.y).length() / bead.z))
			thickness[y * size + x] = clampf(value, 0.0, 1.0)
	return field_image(thickness, size)

static func field_image(thickness: PackedFloat32Array, size: int) -> Image:
	var field: Image = Image.create_empty(size, size, false, Image.FORMAT_RH)
	for y: int in range(size):
		for x: int in range(size):
			field.set_pixel(x, y, Color(thickness[y * size + x], 0.0, 0.0))
	return field
