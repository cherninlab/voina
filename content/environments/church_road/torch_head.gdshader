shader_type spatial;
// Pitch-soaked rag wrapped round the stake head: charred, glossy where the pitch pools, with
// embers glowing in its cracks. heat 0 is a cold dead head, about 0.3 a smouldering one.

instance uniform float heat = 1.0;
instance uniform float seed = 0.0;
varying vec3 local_pos;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float top = clamp(UV.y, 0.0, 1.2); // 0 where the wrap starts, 1 at the rim, above 1 on the cap
	vec3 q = local_pos * 38.0 + vec3(seed * 13.0);
	float grain = noise(q);
	float wrap = 0.5 + 0.5 * sin((UV.x + top * 4.5) * 6.2831);
	vec3 pitch = mix(vec3(0.012, 0.009, 0.008), vec3(0.055, 0.04, 0.03), wrap * 0.45 + grain * 0.35);
	pitch = mix(pitch, vec3(0.022, 0.02, 0.019), smoothstep(0.6, 1.1, top) * 0.5); // ash at the rim
	ALBEDO = pitch;
	ROUGHNESS = mix(0.62, 0.95, clamp(grain * 0.7 + top * 0.4, 0.0, 1.0));
	float cracks = noise(local_pos * 52.0 + vec3(seed * 7.0, -TIME * 0.12, 0.0)) * 0.62 + noise(local_pos * 120.0 + vec3(0.0, TIME * 0.25, seed)) * 0.38;
	float hot = smoothstep(0.6, 0.78, cracks) * smoothstep(0.15, 0.95, top);
	float breathing = 0.8 + 0.2 * sin(TIME * 1.7 + seed * 6.0);
	vec3 ember = mix(vec3(0.7, 0.05, 0.01), vec3(1.0, 0.38, 0.06), clamp(heat, 0.0, 1.0));
	// The rim and cap sit inside the flame: a bed of glowing coal rather than grey ash.
	float bed = smoothstep(0.88, 1.12, top) * (0.55 + 0.45 * cracks);
	EMISSION = ember * (hot * 4.0 + bed * 2.2) * heat * breathing;
}
