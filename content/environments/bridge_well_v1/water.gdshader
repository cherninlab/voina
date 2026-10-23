shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.055, 0.16, 0.13);
uniform vec3 deep_color : source_color = vec3(0.007, 0.032, 0.029);
uniform float absorption : hint_range(0.1, 3.0) = 0.8;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.28;
uniform float displacement_m : hint_range(0.0, 0.03) = 0.008;

void vertex() {
	vec2 ripple_uv = UV * 3.0 + TIME * vec2(0.011, -0.007);
	VERTEX.y += (textureLod(ripple_height, ripple_uv, 0.0).r - 0.5) * displacement_m;
}

void fragment() {
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float thickness = clamp(-behind.z + VERTEX.z, 0.0, 12.0);
	float absorbed = 1.0 - exp(-thickness * absorption);
	vec3 n1 = texture(ripple_normal, UV * 3.0 + TIME * vec2(0.011, -0.007)).rgb;
	vec3 n2 = texture(ripple_normal, UV.yx * 2.3 + TIME * vec2(-0.006, 0.009)).rgb;
	NORMAL_MAP = mix(n1, n2, 0.35);
	NORMAL_MAP_DEPTH = ripple_strength;
	float foam = texture(foam_map, UV * 2.0 + TIME * vec2(0.003, 0.001)).r;
	foam *= (1.0 - smoothstep(0.06, 0.55, thickness)) * 0.22;
	ALBEDO = mix(mix(shallow_color, deep_color, absorbed), vec3(0.28, 0.32, 0.23), foam);
	ROUGHNESS = 0.16 + foam * 0.4;
	SPECULAR = 0.3;
	METALLIC = 0.0;
	ALPHA = mix(0.66, 0.96, absorbed);
}
