shader_type spatial;
render_mode cull_disabled;
// Beard moss hanging from dead limbs (T-092). Each ribbon frays into thin strings of uneven length:
// UV.x runs across the ribbon (its integer part varies per ribbon), UV.y is 0 at the anchor and 1
// at the longest tip. Discarded gaps keep it opaque; the strings sway a little toward their tips.

uniform vec3 color : source_color = vec3(0.43, 0.46, 0.39);
uniform float strings = 9.0;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sway = UV.y * UV.y;
	float phase = TIME * 0.7 + dot(origin.xz, vec2(0.31, 0.17)) + VERTEX.x * 0.6 + VERTEX.z * 0.4;
	VERTEX.x += sin(phase) * 0.07 * sway;
	VERTEX.z += cos(phase * 1.27) * 0.05 * sway;
}

void fragment() {
	float across = UV.x * strings;
	float id = floor(across);
	float local = fract(across);
	float reach = 0.35 + 0.65 * hash(id);
	float start = 0.12 * hash(id + 3.0);
	float thickness = 0.3 * (1.0 - 0.75 * clamp(UV.y / reach, 0.0, 1.0));
	if (UV.y > reach || UV.y < start || abs(local - 0.5 + sin(UV.y * 9.0 + id) * 0.08) > thickness) {
		discard;
	}
	float shade = mix(0.75, 1.1, hash(id + 7.0)) * mix(1.0, 0.75, UV.y);
	ALBEDO = color * COLOR.rgb * shade;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	BACKLIGHT = ALBEDO * 0.4;
}
