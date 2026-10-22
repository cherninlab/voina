shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Long Grass horizon trees: three crossed quads per tree, each showing one of the three pines in
// content/environments/long_grass/horizon_pines.png. INSTANCE_CUSTOM.r picks the pine (0, 1, 2).
// Unlit and unfogged: at 60-160 m they read as darkened sprites against the night sky.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(0.13, 0.15, 0.17);
uniform float alpha_cut = 0.4;

void vertex() {
	UV.x = (UV.x + floor(INSTANCE_CUSTOM.r + 0.5)) / 3.0;
}

void fragment() {
	vec4 pine = texture(atlas, UV);
	ALBEDO = pine.rgb * tint;
	ALPHA = pine.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
