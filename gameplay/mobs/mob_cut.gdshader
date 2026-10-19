shader_type spatial;
render_mode cull_disabled;

// One half of a bisected raider. UV2.x holds each vertex's signed distance (metres) to the cut
// plane and TANGENT the plane's normal, both baked in the pose the cut happened in, so the cut
// rides on the bones while the half ragdolls. Fragments on the other side are discarded. The
// inside of the body is only visible through the opening, so it is shaded as the cut plane would
// be: lit with the plane's normal and coloured by where the view ray meets the plane. That reads
// as a solid flesh cap instead of the hollow shell. (It keeps its own depth: lifting it onto the
// plane would draw it over skin in front.)
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool has_albedo = true;
uniform float side = 1.0;
uniform vec3 flesh : source_color = vec3(0.3, 0.012, 0.01); // HitEffects.BLOOD
uniform vec3 rim : source_color = vec3(0.42, 0.16, 0.12); // skin and fat at the edge of the cut
varying float cut;
varying vec3 cut_normal; // view space, toward the kept side

void vertex() {
	cut = UV2.x * side;
	cut_normal = (MODELVIEW_MATRIX * vec4(TANGENT * side, 0.0)).xyz;
}

float grain(vec2 uv) {
	return fract(sin(dot(floor(uv), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	if (cut < 0.0) {
		discard;
	}
	vec3 normal = normalize(cut_normal);
	float facing = dot(VIEW, normal);
	if (FRONT_FACING) {
		vec3 base = has_albedo ? texture(albedo_tex, UV).rgb : vec3(0.7);
		ALBEDO = base;
		ROUGHNESS = 0.85;
	} else {
		// How far the view ray travels from the cap to this far wall: short near the cut's edge.
		float lift = facing < -0.05 ? cut / -facing : 1.0;
		NORMAL = facing < 0.0 ? -normal : normal;
		// Wet meat, mottled by the far wall's texture coordinates so the pattern sticks to the
		// body, paling toward skin in the last centimetre at the edge.
		float mottle = grain(UV * 60.0) * 0.5 + grain(UV * 23.0) * 0.5;
		vec3 meat = flesh * mix(0.85, 1.45, mottle);
		ALBEDO = mix(rim, meat, smoothstep(0.002, 0.012, lift));
		ROUGHNESS = 0.55;
		SPECULAR = 0.2;
	}
	METALLIC = 0.0;
}
