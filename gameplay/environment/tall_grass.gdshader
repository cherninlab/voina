shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
// Long Grass blades: one clump mesh, instanced. UV.y runs 0 at the root to 1 at the tip; the
// instance colour (MultiMesh) varies the shade per clump.
uniform vec3 root_color : source_color = vec3(0.05, 0.08, 0.06);
uniform vec3 tip_color : source_color = vec3(0.32, 0.4, 0.33);
uniform float wind = 0.18;

varying float height;

void vertex() {
	height = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.1 + world.x * 0.07 + world.z * 0.05) * 0.5 + 0.5;
	float sway = sin(TIME * 2.3 + world.x * 0.9 + world.z * 0.6) * (0.4 + gust);
	// The tip moves most; roots stay planted. Clumps are only yawed and stretched upright, so the
	// local offset stays about metres, in a per-clump direction.
	VERTEX.xz += vec2(sway, sway * 0.6) * wind * UV.y * UV.y;
	// Blades lit as if facing up: a field reads as one soft surface, not flickering cards.
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(root_color, tip_color, height) * COLOR.rgb;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.12);
}
