shader_type spatial;
// Dark trampled graveyard earth laid just above the landscape: dead grass patches, wet hollows
// and a thin dusting of ash, with a ragged edge that dissolves into the surrounding ground.
uniform sampler2D dirt_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 region = vec4(-22.0, -113.0, 14.0, -86.0);
uniform float edge = 3.0;
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = noise(p * 0.45);
	float n2 = noise(p * 1.9 + vec2(11.0));
	float inside = min(min(p.x - region.x, region.z - p.x), min(p.y - region.y, region.w - p.y));
	if (inside / edge + (n - 0.5) * 0.9 + (n2 - 0.5) * 0.35 < 0.3) {
		discard;
	}
	// The torch road's own mud strip (church_road.gd) runs on to z = -90 at the same height.
	float road = -0.5 + sin(max(-p.y - 37.0, 0.0) * 0.055) * 4.0;
	if (p.y > -90.05 && abs(p.x - road) < 1.95) {
		discard;
	}
	vec3 dirt = texture(dirt_map, p * 0.33).rgb;
	vec3 mud = texture(earth_map, p * 0.21).rgb;
	vec3 c = mix(dirt, mud, smoothstep(0.3, 0.7, noise(p * 0.18))) * vec3(0.2, 0.19, 0.17);
	float dead = smoothstep(0.42, 0.75, noise(p * 0.6 + vec2(5.0)));
	c = mix(c, vec3(0.12, 0.1, 0.065) * (0.7 + 0.6 * n2), dead * 0.6);
	float wet = smoothstep(0.6, 0.8, noise(p * 0.3 + vec2(23.0)));
	c *= mix(1.0, 0.55, wet);
	float dust = smoothstep(0.8, 0.95, noise(p * 13.0)) * 0.22 * smoothstep(0.4, 0.8, noise(p * 0.8 + vec2(40.0)));
	c = mix(c, vec3(0.36, 0.36, 0.35), dust * (1.0 - wet));
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.68, wet);
}
