shader_type spatial;
// Wet, trodden mud laid over the north trail in short chunks so each chunk receives its nearby torch
// lights (the Mobile renderer applies at most eight omni lights per mesh instance).
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D trail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float road_length = 60.0;
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
	float across = UV.x; // -1 at one shoulder, +1 at the other
	float footprint = length(fwidth(p));
	float fine = mix(noise(p * 2.1), 0.5, smoothstep(0.03, 0.2, footprint));
	// The landscape trail uses the same mineral earth at the same world scale.
	vec3 earth = texture(trail, p * 0.32).rgb * mix(0.75, 1.02, noise(p * 0.11));
	vec3 grit = texture(gravel, p * 0.41).rgb;
	earth = mix(earth, grit, 0.5 + 0.25 * noise(p * 0.47 + 9.0));
	earth = mix(earth, vec3(dot(earth, vec3(0.3, 0.55, 0.15))), 0.3) * vec3(0.92, 0.88, 0.82);
	// Trodden ruts either side of the crown, and only some stretches hold standing water.
	float rut = exp(-pow((abs(across + (noise(p * 0.3) - 0.5) * 0.2) - 0.42) / 0.14, 2.0));
	float stretch = smoothstep(0.35, 0.75, noise(p * 0.16 + 21.0));
	float pool_noise = noise(p * 0.7 + vec2(13.0, 5.0)) * 0.6 + noise(p * 1.9 - 4.0) * 0.28 + noise(p * 5.3 + 2.0) * 0.12;
	float wet = smoothstep(0.42, 0.8, pool_noise * 0.7 + rut * 0.18 + stretch * 0.2 + fine * 0.08);
	float puddle = smoothstep(0.69, 0.77, pool_noise + (rut * 0.16 - abs(across) * 0.12 - 0.1) + stretch * 0.12);
	vec3 mud = earth * vec3(0.58, 0.55, 0.52);
	vec3 albedo = mix(earth * 0.82, mud, wet);
	albedo = mix(albedo, vec3(0.016, 0.018, 0.02), puddle * 0.92);
	ALBEDO = albedo * mix(0.9, 1.05, fine);
	ROUGHNESS = mix(mix(0.93, 0.55, wet), 0.3, puddle);
	SPECULAR = mix(0.4, 0.5, puddle);
	// Overhanging woods hide most of the sky: dim reflected sky, keep the torch glints (direct light).
	AO = mix(mix(1.0, 0.8, wet), 0.5, puddle);
	// Broken shoulders and soft ends so the overlay never reads as a ribbon.
	float shoulder = abs(across) + (noise(p * 0.85) - 0.5) * 0.42 + (noise(p * 2.6) - 0.5) * 0.18;
	float ends = smoothstep(0.0, 3.5, UV.y) * (1.0 - smoothstep(road_length - 6.0, road_length, UV.y));
	ALPHA = (1.0 - smoothstep(0.5, 0.97, shoulder)) * ends;
}
