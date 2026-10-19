shader_type spatial;
// Embers drifting up from a torch head (GPUParticles3D draw pass).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float energy = 3.0;
uniform float fog_density = 0.0;
varying float fade;

void vertex() {
	mat4 facing = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat4 size = mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * facing * size;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	fade = exp(-fog_density * length(MODEL_MATRIX[3].xyz - CAMERA_POSITION_WORLD));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float spot = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = COLOR.rgb * energy * fade;
	ALPHA = spot * spot * COLOR.a;
}
