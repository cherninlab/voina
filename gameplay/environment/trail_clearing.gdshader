shader_type spatial;
render_mode depth_draw_opaque;
// Long Grass clearing floor: trodden gravel fading out at its rim into whatever lies beneath (the
// field's soil or the road), frayed by the gravel's own grain. Drawn on a flat disc of radius
// `radius` around its own origin, a hair above the road.
uniform sampler2D gravel_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.5, 0.48, 0.45);
uniform float metres = 2.5;
uniform float radius = 10.0;
uniform float core = 0.75; // share of the radius that is fully trodden

varying vec2 ground;
varying float out_from_centre;

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	out_from_centre = length(VERTEX.xz) / radius;
}

void fragment() {
	vec3 gravel = texture(gravel_texture, ground / metres).rgb;
	float grain = dot(texture(gravel_texture, ground / 6.7).rgb, vec3(0.333)) - 0.35;
	ALBEDO = gravel * tint;
	ALPHA = 1.0 - smoothstep(core, 1.0, out_from_centre + grain * 0.4);
	ROUGHNESS = 1.0;
}
