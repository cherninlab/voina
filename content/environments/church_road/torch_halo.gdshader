shader_type spatial;
// Soft warm glow around a torch flame, standing in for bloom and for lit haze in fog.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float heat = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.4, 0.08);
uniform float strength = 0.42;
uniform float fog_density = 0.0;
global uniform float flash_grade; // flash photo: yellower, smaller glow (see torch_flame.gdshader)
varying float fade;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	fade = exp(-fog_density * length(MODEL_MATRIX[3].xyz - CAMERA_POSITION_WORLD));
}

void fragment() {
	float r2 = dot(UV - 0.5, UV - 0.5) * 4.0;
	// Two gaussians windowed to exactly zero at the quad's rim: no visible disc edge.
	float window = (1.0 - r2) * (1.0 - r2);
	float glow = (exp(-r2 * 14.0) * 0.6 + exp(-r2 * 4.5) * 0.4) * window * step(r2, 1.0);
	vec3 colour = mix(tint, vec3(1.0, 0.66, 0.32), flash_grade);
	ALBEDO = colour * glow * strength * (1.0 - flash_grade * 0.35) * heat * fade;
	ALPHA = 1.0;
}
