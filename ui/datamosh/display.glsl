#[versions]

rgba16f = "#define COLOR_FORMAT rgba16f";
rgb10a2 = "#define COLOR_FORMAT rgb10_a2";

#[compute]
#version 450

VERSION_DEFINES

// Step 7: the decoded frame back into the scene colour, before tonemapping, glow and the
// fisheye. Each screen pixel takes the internal pixel it falls in (nearest upscale, so
// blocks stay hard); the padding past the frame edge is never shown.
// debug_view: 1 Y, 2 Cb/Cr, 3 motion vectors (hue = direction, brightness = length,
// 8 px = full), 4 residual before quantization (x4, grey = 0), 5 I/P indicator (corner
// square: red = I, green = P, and a bar for the position inside the GOP).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(COLOR_FORMAT, set = 0, binding = 0) uniform restrict writeonly image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D ref_image;
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D mv_image;
layout(rgba16f, set = 0, binding = 3) uniform restrict readonly image2D residual_image;

layout(push_constant, std430) uniform Params {
	ivec2 screen_size;
	ivec2 size;
	float scale; // internal / screen
	float luminance_multiplier;
	float gop_pos;
	int debug_view;
	uint intra;
	float pad0;
	float pad1;
	float pad2;
} params;

vec3 ycc_to_rgb(vec3 y) {
	return vec3(
		y.x + 1.402 * y.z,
		y.x - 0.344136 * y.y - 0.714136 * y.z,
		y.x + 1.772 * y.y);
}

// Inverse of ycbcr.glsl's encode_curve.
vec3 decode_curve(vec3 e) {
	vec3 t = min(pow(clamp(e, 0.0, 1.0), vec3(2.2)), vec3(0.996));
	return t / (1.0 - t);
}

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void main() {
	ivec2 fc = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(fc, params.screen_size))) {
		return;
	}
	ivec2 p = min(ivec2((vec2(fc) + 0.5) * params.scale), params.size - 1);
	vec3 ycc = imageLoad(ref_image, p).rgb;
	vec3 rgb = ycc_to_rgb(vec3(ycc.x + 128.0, ycc.yz) / 255.0);
	bool debug = params.debug_view >= 1 && params.debug_view <= 4;
	if (params.debug_view == 1) {
		rgb = vec3((ycc.x + 128.0) / 255.0);
	} else if (params.debug_view == 2) {
		rgb = ycc_to_rgb(vec3(0.5, ycc.yz / 255.0));
	} else if (params.debug_view == 3) {
		vec2 mv = imageLoad(mv_image, p >> 4).xy;
		float len = length(mv);
		rgb = len < 0.25 ? vec3(0.0) : hue(atan(-mv.y, mv.x) / 6.2831853) * clamp(len / 8.0, 0.15, 1.0);
	} else if (params.debug_view == 4) {
		vec3 r = imageLoad(residual_image, p).rgb;
		rgb = ycc_to_rgb(vec3(0.5 + r.x * 4.0 / 255.0, r.yz * 4.0 / 255.0));
	} else if (params.debug_view == 5) {
		float u = float(params.screen_size.y) * 0.04;
		vec2 px = vec2(fc);
		if (px.x < u * 2.0 && px.y < u * 2.0) {
			rgb = params.intra != 0u ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.8, 0.0);
			debug = true;
		} else if (px.y < u * 0.5 && px.x < u * 2.0 + (float(params.screen_size.x) - u * 2.0) * params.gop_pos) {
			rgb = vec3(1.0);
			debug = true;
		}
	}
	// Debug colours are display-referred: undo only the gamma, so they land near their value.
	vec3 linear_rgb = debug ? pow(clamp(rgb, 0.0, 1.0), vec3(2.2)) : decode_curve(rgb);
	imageStore(color_image, fc, vec4(linear_rgb / params.luminance_multiplier, 1.0));
}
