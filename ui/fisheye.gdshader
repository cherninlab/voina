shader_type canvas_item;

// Fisheye remap of the rendered frame: the camera renders a wide rectilinear view, and this
// resamples it so the centre is magnified and the edges compress, bowing straight lines.
// The radial mapping is one smooth odd cubic over the whole frame, normalised so the frame
// corners sample the source corners: distortion grows continuously from the centre to the
// corners, with no clamp radius (and so no visible circle) and no black borders.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float source_half_fov = 1.0; // radians, half of the camera's vertical field of view
uniform float centre_half_fov = 0.79; // radians, half of the vertical field of view the frame centre shows

void fragment() {
	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 plane = vec2(centered.x * aspect, centered.y);
	// The centre keeps the narrower view; the rest of the wide source is squeezed toward the edges.
	float barrel = clamp(1.0 - tan(centre_half_fov) / tan(source_half_fov), 0.0, 0.9);
	// rho is 0 at the centre and 1 at the corners. The source radius rho * (1 - b + b * rho^2)
	// has radial scale 1 - b + 3b * rho^2: smooth everywhere, monotonic, and never past the source.
	float rho2 = dot(plane, plane) / (aspect * aspect + 1.0);
	vec2 remapped = plane * (1.0 - barrel + barrel * rho2);
	remapped.x /= aspect;
	vec2 uv = clamp(remapped * 0.5 + 0.5, vec2(0.0), vec2(1.0));
	COLOR = texture(screen_tex, uv);
}
