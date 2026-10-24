shader_type spatial;
// Baked bridges carry real UVs: U runs along each board's grain in metres.
// COLOR.r is Cycles-baked AO (Mobile has no SSAO), COLOR.g per-piece variation
// (scripts/art/procgen). Maps come from the dungeon "wood" material at runtime.
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_map : filter_linear_mipmap, repeat_enable;
uniform float scale = 0.65;
uniform float normal_strength = 0.8;
uniform float wetness = 0.3;
uniform float contact_darkening = 0.55;
uniform vec3 rope_tint : source_color = vec3(0.36, 0.29, 0.2);
instance uniform float rope = 0.0;
varying vec3 world_position;

float noise3(vec3 p) {
	highp vec3 cell = floor(p);
	highp vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	highp vec4 h = vec4(dot(cell, vec3(1.0, 57.0, 113.0))) + vec4(0.0, 1.0, 57.0, 58.0);
	highp vec4 a = fract(sin(h) * 43758.5453);
	highp vec4 b = fract(sin(h + 113.0) * 43758.5453);
	return mix(mix(mix(a.x, a.y, f.x), mix(a.z, a.w, f.x), f.y),
		mix(mix(b.x, b.y, f.x), mix(b.z, b.w, f.x), f.y), f.z);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Rope reuses the oak scan at a fibre scale, stretched along its twist.
	vec2 uv = UV * scale * mix(vec2(1.0), vec2(5.0, 9.0), rope);
	vec3 albedo = texture(albedo_map, uv).rgb;
	float luminance = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	vec3 timber = mix(vec3(luminance), albedo, 0.62) * vec3(0.75, 0.79, 0.8) * mix(0.78, 1.16, COLOR.g);
	vec3 fibre = rope_tint * mix(0.75, 1.2, luminance * 2.0) * mix(0.85, 1.1, COLOR.g);
	vec3 color = mix(timber, fibre, rope);
	float broad = noise3(world_position * 0.105 + vec3(17.0));
	float medium = noise3(world_position * 0.72 + vec3(9.2, 2.7, 5.1));
	color *= mix(vec3(0.8, 0.84, 0.82), vec3(1.04, 1.02, 0.96), broad) * mix(0.9, 1.07, medium);
	// Baked contact shading also dims direct torch light a little.
	float ao = COLOR.r;
	color *= mix(1.0 - contact_darkening, 1.0, ao);
	float lower = 1.0 - smoothstep(-40.0, -24.0, world_position.y);
	float coverage = texture(wet_map, world_position.xz * vec2(0.14, 0.1)).r;
	float wet = smoothstep(0.54, 0.74, coverage * 0.55 + broad * 0.45) * wetness * mix(0.6, 1.0, lower);
	ALBEDO = mix(color, color * vec3(0.64, 0.68, 0.66), wet);
	float dry = texture(roughness_map, uv).r;
	ROUGHNESS = mix(mix(0.75, 0.98, dry), mix(0.32, 0.46, dry), wet);
	NORMAL_MAP = texture(normal_map, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - rope * 0.5);
	AO = ao * mix(1.0, texture(ao_map, uv).r, 0.6);
	AO_LIGHT_AFFECT = 0.2;
	SPECULAR = mix(0.35, 0.42, wet);
}
