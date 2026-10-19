shader_type spatial;
// Smouldering ember patches on the forest floor (T-092): charcoal with slowly breathing orange
// flecks, the only warm colour besides the torches. No lights; the patch hugs the terrain and its
// ragged edge is discarded. UV spans the patch 0..1.

uniform vec3 glow : source_color = vec3(1.0, 0.36, 0.08);
uniform float strength = 2.6;

varying vec3 world_position;

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
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float edge = length(UV * 2.0 - 1.0);
	float shape = value_noise(p * 2.2) * 0.6 + value_noise(p * 5.3 + 9.0) * 0.4 - edge * edge * 0.85;
	if (shape < 0.12) {
		discard;
	}
	float flecks = smoothstep(0.62, 0.9, value_noise(p * 9.0 + 3.0) * 0.7 + value_noise(p * 21.0) * 0.3);
	float breathe = 0.55 + 0.45 * sin(TIME * (0.9 + hash(floor(p * 3.0)) * 1.4) + hash(floor(p * 7.0)) * 6.28);
	float heat = flecks * breathe * smoothstep(0.12, 0.3, shape);
	ALBEDO = mix(vec3(0.03, 0.028, 0.026), vec3(0.08, 0.075, 0.07), value_noise(p * 13.0));
	ROUGHNESS = 0.95;
	EMISSION = glow * heat * strength;
}
