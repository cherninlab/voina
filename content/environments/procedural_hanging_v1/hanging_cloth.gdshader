shader_type spatial;
// Old wool and linen for the banner_*, tapestry_* and drape_* meshes, and hemp for rope_*
// (rope = true: U runs along the rope, V round it, both metres, and the yarn becomes the lay).
// Double sided like the dungeon's "cloth" material. Cloth UVs are metres across (U) and down
// from the nails (V). A MultiMesh instance colour multiplies COLOR: keep it white.
// Vertex colour: R = baked AO (Godot Mobile has no SSAO), G = per-asset variation, B = wear on
// free edges (torn hems, holes): they fade and pick up grime.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 dye : source_color = vec3(0.30, 0.045, 0.03);
uniform vec3 grime : source_color = vec3(0.075, 0.062, 0.048);
uniform float variation : hint_range(0.0, 1.0) = 0.35;
uniform float hem_grime : hint_range(0.0, 1.0) = 0.55;
uniform float threads_per_m = 260.0;
uniform float ao_in_direct : hint_range(0.0, 1.0) = 0.7;
uniform bool rope = false;
uniform float lay_per_m = 38.0;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float ao = COLOR.r;
	// Plain weave: warp and weft alternate; fades out before it can alias.
	vec2 t = uv * threads_per_m;
	float footprint = length(fwidth(t));
	float over = mod(floor(t.x) + floor(t.y), 2.0);
	float yarn = mix(0.5 + 0.5 * sin(t.y * 6.2832), 0.5 + 0.5 * sin(t.x * 6.2832), over);
	if (rope) {
		// Three-strand lay: grooves run diagonally round the rope.
		t = uv * lay_per_m;
		footprint = length(fwidth(t));
		yarn = pow(0.5 + 0.5 * sin((t.x + t.y * 3.0) * 6.2832), 0.6);
	}
	float weave = mix(0.86 + 0.2 * yarn, 1.0, smoothstep(0.35, 0.9, footprint));
	if (rope) {
		weave = mix(0.6 + 0.5 * yarn, 0.9, smoothstep(0.35, 0.9, footprint));
	}
	// Faded dye, water stains, sun-bleached streaks down the drop and grime gathering towards
	// the hem and torn edges.
	vec2 seedling = vec2(COLOR.g * 11.0, COLOR.g * 5.0);
	float stain = smoothstep(0.35, 0.75, noise(uv * 2.7 + seedling) * 0.6 + noise(uv * 7.3) * 0.4);
	float streak = noise(vec2(uv.x * 9.0, uv.y * 0.8) + seedling);
	vec3 base = dye * (1.0 + (COLOR.g - 0.5) * variation) * (0.75 + 0.45 * noise(uv * 1.3 + 5.0));
	base = mix(base, vec3(dot(base, vec3(0.33))) * 1.25, 0.35 * smoothstep(0.55, 0.9, streak));
	float hem = rope ? 0.0 : hem_grime * smoothstep(0.6, 2.4, uv.y) * 0.5;
	float dirt = clamp(COLOR.b * 0.75 + stain * 0.45 + hem, 0.0, 1.0);
	ALBEDO = mix(base, grime, dirt) * weave * mix(1.0, ao, ao_in_direct);
	AO = ao;
	ROUGHNESS = 0.96;
	SPECULAR = 0.2;
	// Wool fuzz: a soft rim that catches the torch at grazing angles.
	RIM = rope ? 0.1 : 0.35;
	RIM_TINT = 0.6;
	BACKLIGHT = ALBEDO * 0.25;
}
