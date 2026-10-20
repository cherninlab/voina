shader_type spatial;
// Candle, torch and grave-fire flames: one MultiMesh of upright quads billboarded around Y.
// Instance colour: r = phase seed, g = brightness, b = sway.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 core : source_color = vec3(1.0, 0.86, 0.55);
uniform vec3 outer : source_color = vec3(1.0, 0.34, 0.06);
uniform float energy = 1.6;
global uniform float flash_grade; // flash photo: clipped yellow-white core, orange edge

varying float seed;
varying float bright;

void vertex() {
	seed = COLOR.r * 61.0;
	bright = COLOR.g;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float width = length(MODEL_MATRIX[0].xyz);
	float tall = length(MODEL_MATRIX[1].xyz);
	vec3 to_camera = CAMERA_POSITION_WORLD - origin;
	to_camera.y = 0.0;
	to_camera = length(to_camera) > 0.001 ? normalize(to_camera) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_camera));
	float lift = clamp(VERTEX.y, 0.0, 1.0);
	float flicker = 1.0 + 0.2 * sin(TIME * 11.0 + seed) + 0.12 * sin(TIME * 23.0 + seed * 1.7) + 0.08 * sin(TIME * 5.3 + seed * 0.3);
	vec3 world = origin + right * VERTEX.x * width + vec3(0.0, VERTEX.y * tall * flicker, 0.0);
	world += right * sin(TIME * 6.3 + seed * 2.0) * 0.18 * width * lift * lift * (0.5 + COLOR.b);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float x = (UV.x - 0.5) * 2.0;
	float y = 1.0 - UV.y;
	float profile = sqrt(max(y, 0.0)) * pow(max(1.0 - y, 0.0), 0.75) * 1.9;
	float body = 1.0 - smoothstep(profile * 0.35, profile + 0.02, abs(x));
	float hot = (1.0 - smoothstep(0.0, profile * 0.5 + 0.05, abs(x))) * (1.0 - smoothstep(0.15, 0.6, y));
	vec3 edge = mix(outer, vec3(1.0, 0.62, 0.22), flash_grade);
	vec3 centre = mix(core, vec3(1.0, 0.97, 0.88), flash_grade);
	vec3 color = mix(edge, centre, clamp(hot * (1.4 + flash_grade * 0.8), 0.0, 1.0));
	ALBEDO = color * energy * bright;
	ALPHA = clamp(body, 0.0, 1.0);
}
