shader_type spatial;
// Dark trampled graveyard earth laid just above the landscape: the village's gravel-and-mineral
// dirt, darkened and trodden, with dead grass patches, wet hollows and a thin dusting of ash.
// Toward its ragged edge it turns, over several metres, into exactly what the landscape draws
// there (village_arena.gd make_landscape_material, copied below), so the forest floor runs into
// the yard with no seam. Keep landscape_albedo in step with that shader.
uniform sampler2D dirt_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 region = vec4(-29.0, -119.0, 20.0, -76.0);
uniform float edge = 6.0; // metres from the region's border to full yard earth
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
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 bedrock(vec3 p, vec3 n) {
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.001);
	return texture(rock, p.yz * 0.12).rgb * weights.x + texture(rock, p.xz * 0.12).rgb * weights.y + texture(rock, p.xy * 0.12).rgb * weights.z;
}

// The landscape's own colour here, and how exposed its rock is (for its normal detail).
vec3 landscape_albedo(vec3 at, vec3 n, out float exposed) {
	vec2 p = at.xz;
	vec2 warped = p + vec2(noise(p * 0.035), noise(p * 0.035 + 47.0)) * 18.0;
	float patch = noise(warped * 0.065);
	float elevation = smoothstep(5.0, 20.0, at.y + patch * 9.0);
	float cliff = 1.0 - smoothstep(0.67, 0.94, n.y);
	exposed = clamp(max(cliff, elevation) + (patch - 0.5) * 0.25, 0.0, 1.0);
	vec3 earth = texture(soil, p * 0.18).rgb * mix(vec3(0.60, 0.78, 0.47), vec3(0.9, 0.98, 0.68), noise(warped * 0.027));
	vec3 stone = bedrock(at, n);
	float strata = 0.78 + 0.22 * smoothstep(-0.3, 0.3, sin(at.y * 0.65 + at.x * 0.18 + noise(p * 0.035) * 3.0));
	stone *= mix(vec3(0.33, 0.39, 0.42), vec3(0.63, 0.66, 0.65), patch) * strata;
	vec3 color = mix(earth, stone, exposed) * (0.87 + 0.13 * noise(warped * 0.018));
	float center = -0.5 + sin(max(-p.y - 37.0, 0.0) * 0.055) * 4.0;
	float width = 1.5 + noise(p * 0.22) * 0.8;
	float trail_mask = (1.0 - smoothstep(width, width + 1.0, abs(p.x - center) + (noise(p * 0.9) - 0.5) * 0.65));
	trail_mask *= smoothstep(29.0, 35.0, -p.y) * (1.0 - smoothstep(98.0, 112.0, -p.y));
	return mix(color, texture(trail, p * 0.32).rgb * mix(0.75, 1.02, noise(p * 0.11)), trail_mask);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 n = normalize(world_normal);
	float n1 = noise(p * 0.45);
	float n2 = noise(p * 1.9 + vec2(11.0));
	// 0 at the region's border, 1 from `edge` inside it; broken up into tongues of earth and grass.
	float inside = min(min(p.x - region.x, region.z - p.x), min(p.y - region.y, region.w - p.y));
	float yard = smoothstep(0.0, 1.0, inside / edge + (noise(p * 0.21) - 0.5) * 0.7 + (n1 - 0.5) * 0.35 - 0.1);
	// The torch road's own mud strip (church_road.gd) runs on to z = -90 at the same height: leave
	// it to the strip, and hand its shoulders back to the landscape the strip was made to sit on.
	float road = -0.5 + sin(max(-p.y - 37.0, 0.0) * 0.055) * 4.0;
	float off_road = abs(p.x - road) - 1.95;
	if (p.y > -90.05 && off_road < 0.0) {
		discard;
	}
	yard *= mix(1.0, smoothstep(0.0, 2.5, off_road), smoothstep(-93.0, -90.05, p.y));
	if (yard <= 0.002) {
		discard;
	}
	float exposed;
	vec3 land = landscape_albedo(world_pos, n, exposed);
	// The village's dirt (village_arena.gd make_ground_material), trodden dark and cold.
	vec2 warped = p + vec2(noise(p * 0.17), noise(p * 0.17 + 31.0)) * 0.8;
	float mineral = smoothstep(0.28, 0.72, noise(warped * 0.16));
	vec3 c = mix(texture(dirt_map, warped * 0.4).rgb, texture(earth_map, warped * 0.23).rgb, 0.6 + mineral * 0.35);
	c *= mix(vec3(0.72, 0.68, 0.60), vec3(1.04, 1.0, 0.91), noise(p * 0.09)) * mix(0.9, 1.04, n1);
	c *= vec3(0.46, 0.44, 0.42);
	// Dead turf keeps a real texture (the landscape's grass, browned and dimmed to the earth's
	// level): a flat colour here read as lighter, plastic patches showing through the dirt.
	float dead = smoothstep(0.42, 0.75, noise(p * 0.6 + vec2(5.0)));
	vec3 turf = texture(soil, p * 0.45).rgb;
	turf = mix(vec3(dot(turf, vec3(0.299, 0.587, 0.114))), turf, 0.35) * vec3(0.62, 0.52, 0.34) * (0.8 + 0.4 * n2);
	c = mix(c, turf * 0.75, dead * 0.5);
	// Wet hollows only darken: a gloss with no relief under it shone like plastic near lamps.
	float wet = smoothstep(0.6, 0.8, noise(p * 0.3 + vec2(23.0)));
	c *= mix(1.0, 0.62, wet);
	float dust = smoothstep(0.8, 0.95, noise(p * 13.0)) * 0.22 * smoothstep(0.4, 0.8, noise(p * 0.8 + vec2(40.0)));
	c = mix(c, vec3(0.36, 0.36, 0.35), dust * (1.0 - wet));
	ALBEDO = mix(land, c, yard);
	float land_rough = max(0.85, texture(rock_roughness, p * 0.12).r);
	ROUGHNESS = mix(land_rough, mix(0.97, 0.86, wet), yard);
	SPECULAR = mix(0.5, 0.3, yard);
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.001);
	vec2 nx = texture(rock_normal, world_pos.yz * 0.12).xy * 2.0 - 1.0;
	vec2 ny = texture(rock_normal, world_pos.xz * 0.12).xy * 2.0 - 1.0;
	vec2 nz = texture(rock_normal, world_pos.xy * 0.12).xy * 2.0 - 1.0;
	vec3 detail = vec3(0.0, nx.x, nx.y) * weights.x + vec3(ny.x, 0.0, ny.y) * weights.y + vec3(nz.x, nz.y, 0.0) * weights.z;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + detail * exposed * 0.4 * (1.0 - yard)), 0.0)).xyz);
}
