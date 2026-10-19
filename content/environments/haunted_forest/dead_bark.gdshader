shader_type spatial;
// Weathered dead bark (T-092). Reuses the KitBash Valhalla LogBark maps, pulled toward cold grey,
// with damp moss on upward faces and around the base of each instance.

uniform sampler2D basecolor : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.5, 0.51, 0.53);
uniform vec3 moss_tint : source_color = vec3(0.24, 0.28, 0.2);
uniform float moss = 0.55;
uniform float grey = 0.75;

varying vec3 world_normal;
varying vec3 world_position;
varying float base_height;

void vertex() {
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	base_height = world_position.y - MODEL_MATRIX[3].y;
}

void fragment() {
	vec3 bark = texture(basecolor, UV).rgb;
	float luminance = dot(bark, vec3(0.299, 0.587, 0.114));
	bark = mix(bark, vec3(luminance), grey) * tint;
	float patches = sin(world_position.x * 2.3 + world_position.y * 1.1) * sin(world_position.z * 1.9 - world_position.y * 0.8);
	float cover = smoothstep(0.15, 0.7, world_normal.y + patches * 0.3);
	cover += (1.0 - smoothstep(0.0, 1.3, base_height)) * (0.45 + patches * 0.25);
	cover = clamp(cover, 0.0, 1.0) * moss;
	ALBEDO = mix(bark, moss_tint * (0.55 + luminance), cover);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	ROUGHNESS = mix(texture(roughness_map, UV).r, 1.0, 0.35 + cover * 0.4);
	SPECULAR = 0.35;
}
