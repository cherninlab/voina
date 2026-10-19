shader_type spatial;
// Procedural wet slate shingles for the nave roof, spire and turret cap. UV is in metres:
// x along the courses, y down the slope.
uniform vec3 slate : source_color = vec3(0.11, 0.115, 0.125);
uniform float moss = 0.55;
uniform float tile_width = 0.3;
uniform float tile_height = 0.19;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV;
	float row = floor(p.y / tile_height);
	float shift = mod(row, 2.0) * 0.5 + hash(vec2(row, 3.0)) * 0.2;
	vec2 cell = vec2(floor(p.x / tile_width + shift), row);
	vec2 f = vec2(fract(p.x / tile_width + shift), fract(p.y / tile_height));
	float r = hash(cell);
	float gap = smoothstep(0.0, 0.07, f.x) * smoothstep(1.0, 0.93, f.x);
	float shade = mix(0.45, 1.0, smoothstep(0.0, 0.3, f.y));
	vec3 c = slate * (0.65 + 0.7 * r) * shade * mix(0.35, 1.0, gap);
	float missing = step(0.982, hash(cell + 17.0));
	float m = smoothstep(0.5, 0.85, noise(p * 0.6) * 0.75 + noise(p * 3.1) * 0.35) * moss;
	c = mix(c, vec3(0.035, 0.05, 0.028), m);
	c = mix(c, vec3(0.008), missing);
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = clamp(0.42 + r * 0.25 + m * 0.4 + missing, 0.0, 1.0);
	SPECULAR = 0.45;
	NORMAL_MAP = normalize(vec3(0.5 + (r - 0.5) * 0.3, 0.5 + (0.5 - f.y) * 0.5, 1.0));
	NORMAL_MAP_DEPTH = 0.6;
}
