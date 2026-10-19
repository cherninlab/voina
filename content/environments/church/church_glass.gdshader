shader_type spatial;
// Leaded lancet/rose glass. glow > 0 lights it from within with a slow, uneven flicker; broken
// punches black holes. UV is in metres across the opening.
uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float glow = 0.0;
uniform float broken = 0.0;
uniform float height = 4.0;
uniform float quarry = 0.24;
instance uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV;
	float d1 = abs(fract((p.x + p.y) / quarry) - 0.5);
	float d2 = abs(fract((p.x - p.y) / quarry) - 0.5);
	float lead = smoothstep(0.41, 0.47, max(d1, d2));
	float pane = hash(floor(vec2((p.x + p.y) / quarry, (p.x - p.y) / quarry)) + seed);
	float t = TIME * 0.6 + seed * 13.0;
	float flicker = 0.72 + 0.14 * sin(t * 1.7) + 0.09 * sin(t * 4.3 + 1.3) + 0.05 * sin(t * 9.1);
	flicker *= 1.0 - 0.6 * smoothstep(0.78, 0.96, noise(vec2(t * 0.35, seed * 3.0)));
	float inner = mix(1.0, 0.4, clamp(p.y / height, 0.0, 1.0));
	float holes = step(1.0 - broken * 0.55, noise(p * 3.3 + vec2(seed * 5.0)) * 0.8 + noise(p * 11.0) * 0.2);
	vec3 glass = mix(vec3(0.018, 0.022, 0.026), glow_color * 0.05, pane * 0.6);
	ALBEDO = mix(glass, vec3(0.01), lead) * (1.0 - holes);
	// Old, grimy quarries: a dull sheen rather than a mirror of the bright sky.
	ROUGHNESS = mix(mix(0.42 + pane * 0.2, 0.85, lead), 1.0, holes);
	SPECULAR = 0.25 * (1.0 - holes);
	EMISSION = glow_color * glow * flicker * inner * (0.55 + 0.9 * pane) * (1.0 - lead) * (1.0 - holes);
}
