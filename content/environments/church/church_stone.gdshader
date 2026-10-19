shader_type spatial;
// Weathered church stone: world-triplanar maps, vertical grime streaks, creeping moss and an ash
// dusting on upward faces. Vertex colour varies individual blocks and headstones.
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.45;
uniform vec3 tint : source_color = vec3(0.4, 0.41, 0.39);
uniform float moss = 0.6;
uniform float ash = 0.25;
uniform float grime = 0.55;
uniform float normal_strength = 0.8;
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
	vec3 n = normalize(world_normal);
	vec3 blend = pow(abs(n), vec3(4.0));
	blend /= blend.x + blend.y + blend.z;
	vec2 uv_x = world_pos.zy * scale;
	vec2 uv_y = world_pos.xz * scale;
	vec2 uv_z = world_pos.xy * scale;
	vec3 color = texture(albedo_map, uv_x).rgb * blend.x + texture(albedo_map, uv_y).rgb * blend.y + texture(albedo_map, uv_z).rgb * blend.z;
	float rough = texture(roughness_map, uv_x).r * blend.x + texture(roughness_map, uv_y).r * blend.y + texture(roughness_map, uv_z).r * blend.z;
	vec3 tx = texture(normal_map, uv_x).xyz * 2.0 - 1.0;
	vec3 ty = texture(normal_map, uv_y).xyz * 2.0 - 1.0;
	vec3 tz = texture(normal_map, uv_z).xyz * 2.0 - 1.0;
	tx.xy *= normal_strength;
	ty.xy *= normal_strength;
	tz.xy *= normal_strength;
	// Whiteout blend of the three tangent-space maps into one world normal.
	vec3 nx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	vec3 ny = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	vec3 nz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 bent = normalize(nx.zyx * blend.x + ny.xzy * blend.y + nz.xyz * blend.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	float broad = noise(world_pos.xz * 0.35 + vec2(world_pos.y * 0.21));
	float streak = noise(vec2((world_pos.x + world_pos.z) * 3.1, world_pos.y * 0.22));
	color *= tint * COLOR.rgb;
	color *= mix(1.0, 0.5 + 0.5 * streak, grime * (1.0 - abs(n.y)));
	color *= 0.82 + 0.32 * broad;
	float up = smoothstep(0.35, 0.85, n.y);
	float moss_mask = smoothstep(0.42, 0.78, noise(world_pos.xz * 0.9 + vec2(world_pos.y * 0.7)) * 0.7 + broad * 0.5) * moss;
	color = mix(color, vec3(0.045, 0.07, 0.032), moss_mask * max(up, 0.4 * (1.0 - streak)));
	float ash_mask = up * smoothstep(0.7, 0.9, noise(world_pos.xz * 14.0 + vec2(world_pos.y))) * smoothstep(0.35, 0.75, broad) * ash;
	color = mix(color, vec3(0.43, 0.43, 0.42), ash_mask);
	ALBEDO = color;
	ROUGHNESS = clamp(mix(rough, 1.0, 0.35), 0.7, 1.0);
}
