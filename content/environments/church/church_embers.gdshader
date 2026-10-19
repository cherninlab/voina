shader_type spatial;
// Smouldering ground cracks near the church: charred earth with ragged edges and a slowly
// breathing orange glow along Voronoi fissures. UV spans the patch from 0 to 1.
uniform vec3 ember : source_color = vec3(1.0, 0.33, 0.06);
uniform float glow = 4.0;
uniform float crack_scale = 1.7;
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// Distance to the nearest Voronoi cell border (two-pass method).
float border(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; }
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float radial = 1.0 - length(UV * 2.0 - 1.0);
	float n = noise(p * 1.3);
	float burn = radial + (n - 0.5) * 0.55 + (noise(p * 4.1) - 0.5) * 0.18;
	if (burn < 0.06) {
		discard;
	}
	float e = border(p * crack_scale + vec2(n * 0.6));
	float heat = smoothstep(0.12, 0.55, burn);
	float crack = (1.0 - smoothstep(0.015, 0.06 + heat * 0.03, e)) * heat;
	float halo = (1.0 - smoothstep(0.02, 0.22, e)) * heat * 0.25;
	float pulse = 0.65 + 0.25 * sin(TIME * 0.8 + p.x * 1.3 + p.y * 0.7) + 0.1 * sin(TIME * 2.3 + p.y * 3.0);
	vec3 char = mix(vec3(0.028, 0.024, 0.02), vec3(0.075, 0.068, 0.062), noise(p * 2.7));
	ALBEDO = mix(char, vec3(0.2, 0.06, 0.01), crack);
	ROUGHNESS = 0.95;
	EMISSION = ember * glow * pulse * (crack + halo);
}
