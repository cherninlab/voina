shader_type spatial;
// Weathering for the imported chapel ruin: its own PBR maps, desaturated and darkened toward the
// yard's grey stone, grime low on the walls, streaks, moss on upward faces and a little ash.
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.52, 0.53, 0.5);
uniform float desaturate = 0.6;
uniform float moss = 0.75;
uniform float base_height = 0.0;
varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 c = texture(albedo_map, UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(luma), desaturate) * tint;
	float h = world_pos.y - base_height;
	float broad = noise(world_pos.xz * 0.4 + vec2(world_pos.y * 0.3));
	float streak = noise(vec2((world_pos.x + world_pos.z) * 2.7, world_pos.y * 0.2));
	c *= mix(0.5, 1.0, smoothstep(0.0, 4.0, h + (broad - 0.5) * 2.0));
	c *= mix(1.0, 0.55 + 0.45 * streak, 0.55 * (1.0 - abs(n.y)));
	float up = smoothstep(0.3, 0.8, n.y);
	float moss_mask = smoothstep(0.4, 0.75, noise(world_pos.xz * 0.8 + vec2(world_pos.y * 0.6)) * 0.7 + broad * 0.5) * moss;
	moss_mask *= max(up, 0.45 * (1.0 - smoothstep(0.0, 3.0, h)));
	c = mix(c, vec3(0.04, 0.065, 0.03), moss_mask);
	float ash = up * smoothstep(0.72, 0.9, noise(world_pos.xz * 13.0)) * smoothstep(0.35, 0.75, broad) * 0.15;
	c = mix(c, vec3(0.4, 0.4, 0.39), ash);
	ALBEDO = c;
	vec3 orm = texture(orm_map, UV).rgb;
	ROUGHNESS = clamp(mix(orm.g, 1.0, 0.4), 0.72, 1.0);
	METALLIC = 0.0;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
}
