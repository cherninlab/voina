shader_type spatial;
// Still black bog water and wet mud beside the trail (T-092). The patch hugs the terrain; puddle
// edges are discarded, so it stays opaque with no transparency sorting. Reflections come from the
// sky radiance and nearby lights. UV spans the patch 0..1.

uniform vec3 mud : source_color = vec3(0.075, 0.066, 0.055);
uniform vec3 water : source_color = vec3(0.01, 0.013, 0.017);
uniform float seed = 0.0;
// Mobile has no screen-space reflections: still water mirrors the fog-hazed sky at grazing angles.
uniform vec3 sky_tint : source_color = vec3(0.42, 0.48, 0.52);

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

float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.1 + 17.0) * 0.3 + value_noise(p * 4.3 + 31.0) * 0.15;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float edge = length(UV * 2.0 - 1.0);
	float shape = fbm(p * 0.3 + seed) + 0.12 - edge * edge * 0.95;
	if (shape < 0.06) {
		discard;
	}
	float wet = smoothstep(0.06, 0.16, shape);
	float pool = smoothstep(0.2, 0.25, shape);
	vec2 ripple = vec2(value_noise(p * 2.7 + TIME * 0.11), value_noise(p * 2.7 - TIME * 0.09 + 7.0)) - 0.5;
	ALBEDO = mix(mud * mix(1.0, 0.55, wet), water, pool);
	ROUGHNESS = mix(mix(0.85, 0.4, wet), 0.03, pool);
	SPECULAR = mix(0.35, 0.75, pool);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(ripple.x, 0.0, ripple.y, 0.0)).xyz * 0.06 * pool);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = sky_tint * mix(0.04, 0.75, fresnel) * pool;
}
