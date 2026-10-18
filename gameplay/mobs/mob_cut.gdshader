shader_type spatial;
render_mode cull_disabled;

// One half of a bisected raider. UV2.x holds each vertex's signed distance to the cut plane,
// baked in the pose the cut happened in, so the cut rides on the bones while the half ragdolls.
// Fragments on the other side are discarded and the exposed back faces render as flesh.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool has_albedo = true;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.8, 1.0);
uniform float side = 1.0;
uniform vec3 flesh : source_color = vec3(0.5, 0.04, 0.04);
varying float cut;

void vertex() {
	cut = UV2.x * side;
}

void fragment() {
	if (cut < 0.0) {
		discard;
	}
	vec3 base = has_albedo ? texture(albedo_tex, UV).rgb : vec3(0.7);
	ALBEDO = FRONT_FACING ? base * tint.rgb : flesh;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
