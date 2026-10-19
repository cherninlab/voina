shader_type spatial;
// Dead grass, reeds and hanging moss strands. COLOR.a weights the wind sway (0 at the root or
// branch, 1 at the free end).
render_mode cull_disabled;
uniform vec3 tint : source_color = vec3(1.0);
uniform float sway = 0.06;
uniform float backlight = 0.35;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = TIME * 1.2 + world.x * 0.35 + world.z * 0.27;
	float weight = COLOR.a * COLOR.a;
	VERTEX.x += sin(phase) * sway * weight;
	VERTEX.z += cos(phase * 0.73) * sway * 0.6 * weight;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.95;
	BACKLIGHT = ALBEDO * backlight;
}
