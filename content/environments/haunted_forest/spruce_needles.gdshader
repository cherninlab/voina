shader_type spatial;
render_mode cull_disabled;
// Opaque spruce fronds (T-092): near-black green silhouettes for the fog to layer.

uniform vec3 color : source_color = vec3(0.06, 0.08, 0.065);

void fragment() {
	float needles = 0.82 + 0.18 * sin(UV.x * 61.0) * sin(UV.y * 23.0);
	ALBEDO = color * COLOR.rgb * needles;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	BACKLIGHT = ALBEDO * 0.25;
}
