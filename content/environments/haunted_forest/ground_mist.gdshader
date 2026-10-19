shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, skip_vertex_transform;
// Low ground mist hugging the forest floor (T-092). Each instance is a unit quad (x -0.5..0.5,
// y 0..1 from the ground up) scaled to a wide low card; it turns about world up to face the
// camera, thins toward its top and edges, drifts slowly and fades softly into the ground.

uniform vec3 color : source_color = vec3(0.42, 0.47, 0.5);
uniform float opacity = 0.3;
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
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	vec3 to_camera = camera - origin;
	to_camera.y = 0.0;
	to_camera = normalize(to_camera + vec3(0.0001, 0.0, 0.0));
	vec3 side = vec3(to_camera.z, 0.0, -to_camera.x);
	vec3 point = origin + side * VERTEX.x * width + vec3(0.0, VERTEX.y * height, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(point, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_camera, 0.0)).xyz);
	float distance_to = length((camera - origin).xz);
	fade = smoothstep(1.0, 6.0, distance_to) * (1.0 - smoothstep(50.0, 75.0, distance_to));
	seed = origin.x * 0.13 + origin.z * 0.29;
}

void fragment() {
	float sides = smoothstep(0.0, 0.3, UV.x) * (1.0 - smoothstep(0.7, 1.0, UV.x));
	float rise = smoothstep(0.0, 0.12, UV.y) * pow(1.0 - UV.y, 1.6);
	vec2 drift = vec2(UV.x * 2.6 + TIME * 0.018 + seed, UV.y * 1.4 - TIME * 0.006);
	float cloud = value_noise(drift) * 0.6 + value_noise(drift * 2.3 + 11.0) * 0.4;
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_depth = -scene.z / scene.w;
	float soft = clamp((scene_depth + VERTEX.z) / 1.4, 0.0, 1.0);
	ALBEDO = color;
	ALPHA = clamp(sides * rise * smoothstep(0.2, 0.75, cloud) * soft * fade * opacity, 0.0, 1.0);
}
