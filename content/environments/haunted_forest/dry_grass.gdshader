shader_type spatial;
render_mode cull_disabled;
// Dry reeds and dead grass (T-092). Colour comes from the vertex/instance shade only, so the
// village grass mesh can reuse it outside the palisade; living_share keeps a few dark live clumps.

uniform vec3 straw : source_color = vec3(0.47, 0.43, 0.34);
uniform vec3 living : source_color = vec3(0.1, 0.13, 0.075);
uniform float living_share = 0.25;
uniform float brightness = 1.0;

varying float alive;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.6));
	vec3 origin = MODEL_MATRIX[3].xyz;
	float n = value_noise(origin.xz * 0.11) * 0.75 + hash(origin.xz) * 0.25;
	alive = smoothstep(1.0 - living_share - 0.08, 1.0 - living_share + 0.08, n);
}

void fragment() {
	float shade = dot(COLOR.rgb, vec3(0.3333)) * 1.25;
	vec3 base = mix(straw, living, alive) * shade * brightness;
	ALBEDO = base;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	BACKLIGHT = base * 0.35;
}
