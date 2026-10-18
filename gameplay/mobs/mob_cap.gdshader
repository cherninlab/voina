shader_type spatial;
render_mode cull_disabled;

// The solid face of a bisect cut (MobRagdoll.cap_arrays): wet meat, mottled across the face. UV
// holds the face's own position in the plane (metres) at the moment of the cut, so the pattern
// sticks to the face. Both halves share the face; with culling off each lights its own side.
uniform vec3 flesh : source_color = vec3(0.3, 0.012, 0.01); // HitEffects.BLOOD
uniform vec3 meat : source_color = vec3(0.56, 0.09, 0.07); // lighter muscle, so the face reads as flesh

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

// Smooth value noise: soft blotches rather than square cells.
float grain(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x), mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float mottle = grain(UV * 70.0) * 0.45 + grain(UV * 22.0) * 0.55;
	ALBEDO = mix(flesh, meat, mottle);
	// Matte: a glossier face picks up the sky and goes pink-grey from below.
	ROUGHNESS = 0.7;
	SPECULAR = 0.1;
	METALLIC = 0.0;
}
