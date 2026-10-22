shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Long Grass horizon trees: three crossed quads per tree, each showing one of the three pines in
// content/environments/long_grass/horizon_pines.png. INSTANCE_CUSTOM.r picks the pine (0, 1, 2).
// Unlit and unfogged: at 60-160 m they read as darkened sprites against the night sky.
// The crowns sway with the same gust bands as the grass (tall_grass.gdshader), per vertex only.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(0.13, 0.15, 0.17);
uniform float alpha_cut = 0.4;
uniform float sway = 0.35; // crown lean in a gust, metres
uniform vec2 wind_dir = vec2(0.0, -1.0);
uniform float wind_speed = 4.0;
uniform float gust_size = 18.0;

void vertex() {
	float up = 1.0 - UV.y; // 0 at the trunk foot, 1 at the crown
	UV.x = (UV.x + floor(INSTANCE_CUSTOM.r + 0.5)) / 3.0;
	vec2 at = MODEL_MATRIX[3].xz;
	float front = (dot(at, wind_dir) - TIME * wind_speed) / gust_size;
	float gust = pow(0.5 + 0.5 * sin(front * 6.2832), 3.0);
	float idle = sin(TIME * 0.7 + at.x * 0.13 + at.y * 0.11) * 0.15;
	vec3 lean = vec3(wind_dir.x, 0.0, wind_dir.y) * (gust + idle);
	mat3 basis = mat3(MODEL_MATRIX);
	VERTEX.xz += (transpose(basis) * lean).xz / dot(basis[0], basis[0]) * sway * up * up;
}

void fragment() {
	vec4 pine = texture(atlas, UV);
	ALBEDO = pine.rgb * tint;
	ALPHA = pine.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
