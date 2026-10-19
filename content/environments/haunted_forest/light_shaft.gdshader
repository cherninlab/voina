shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled, skip_vertex_transform;
// Pale god-ray shafts slanting through canopy gaps (T-092). Each instance is a unit quad: x across
// (-0.5..0.5), y along the shaft (0 at the canopy, 1 at the ground). The instance basis X is the
// width and Y the shaft itself. The quad turns about its own axis to face the camera and fades
// against nearby geometry, with distance and when seen end-on. Additive, so it never darkens.

uniform vec3 color : source_color = vec3(0.8, 0.84, 0.88);
uniform float intensity = 0.07;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying float fade;
varying float seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec3 axis = MODEL_MATRIX[1].xyz;
	vec3 direction = normalize(axis);
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	vec3 point = origin + axis * VERTEX.y;
	vec3 to_camera = normalize(camera - point);
	vec3 side = normalize(cross(direction, to_camera));
	point += side * VERTEX.x * width * mix(0.6, 1.35, VERTEX.y);
	VERTEX = (VIEW_MATRIX * vec4(point, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_camera, 0.0)).xyz);
	float end_on = abs(dot(direction, to_camera));
	float distance_to = length(camera - (origin + axis * 0.6));
	fade = (1.0 - smoothstep(0.7, 0.95, end_on)) * smoothstep(3.0, 9.0, distance_to) * (1.0 - smoothstep(45.0, 70.0, distance_to));
	seed = origin.x * 0.37 + origin.z * 0.11;
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	across = across * across * (3.0 - 2.0 * across);
	float along = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float streaks = 0.45 + 0.55 * value_noise(vec2(UV.x * 6.0 + seed, UV.y * 1.2 - TIME * 0.025));
	float breathe = 0.75 + 0.25 * sin(TIME * 0.35 + seed * 3.0);
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_depth = -scene.z / scene.w;
	float soft = clamp((scene_depth + VERTEX.z) / 2.0, 0.0, 1.0);
	ALBEDO = color;
	ALPHA = clamp(across * along * streaks * breathe * fade * soft * intensity, 0.0, 1.0);
}
