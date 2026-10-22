shader_type spatial;
// Long Grass ground: the field's soil, and the road ribbon, whose trodden dirt frays into that same
// soil toward both edges. Both sample the textures from above in world metres, so where the ribbon
// ends it is already the field's soil and no line shows. UV.x runs across the ribbon (0..1); the
// field plane sets soil_only.
uniform sampler2D path_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 path_tint : source_color = vec3(0.5, 0.48, 0.45);
uniform vec3 soil_tint : source_color = vec3(0.32, 0.36, 0.3);
uniform float path_metres = 1.5;
uniform float soil_metres = 2.5;
uniform float core = 0.55; // share of the ribbon (from its centre line) that is pure path
uniform bool soil_only = false;

varying vec2 ground;

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec3 soil = texture(soil_texture, ground / soil_metres).rgb * soil_tint;
	vec3 colour = soil;
	if (!soil_only) {
		vec3 path = texture(path_texture, ground / path_metres).rgb * path_tint;
		// The soil's own coarse grain breaks the edge up, so it frays instead of fading evenly.
		float grain = dot(texture(soil_texture, ground / 6.7).rgb, vec3(0.333)) - 0.35;
		float across = abs(UV.x * 2.0 - 1.0);
		colour = mix(path, soil, smoothstep(core, 1.0, across + grain * 0.6));
	}
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}
