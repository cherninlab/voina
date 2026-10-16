shader_type canvas_item;

// Fisheye remap of the rendered frame: the camera renders a wide rectilinear view, and this
// resamples it with an equidistant projection so the edges compress and straight lines bow.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.6;
uniform float source_half_fov = 1.13; // radians, half of the camera's vertical field of view
uniform float view_half_angle = 0.95; // radians of view mapped to the frame's half height

void fragment() {
	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 plane = vec2(centered.x * aspect, centered.y);
	float radius = length(plane);
	vec2 uv = SCREEN_UV;
	if (radius > 0.0001) {
		float angle = radius * view_half_angle;
		float source = tan(min(angle, source_half_fov - 0.01)) / tan(source_half_fov);
		vec2 remapped = plane / radius * source;
		remapped.x /= aspect;
		vec2 fish = remapped * 0.5 + 0.5;
		uv = mix(SCREEN_UV, fish, strength);
	}
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = texture(screen_tex, uv);
	}
}
