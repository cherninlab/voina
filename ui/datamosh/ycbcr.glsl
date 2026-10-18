#[compute]
#version 450

// Step 1: the rendered frame to YCbCr 4:2:0 at the codec's internal resolution.
// The scene colour is linear HDR (before ACES). It is first squashed into 0..1 by an
// invertible curve, (c / (1 + c))^(1 / 2.2), so the quantizer works on a perceptual signal as
// a real encoder works on gamma-coded video; display.glsl undoes the curve.
// Values are in 8-bit units: Y is level-shifted to -128..127, Cb/Cr are -127.5..127.5,
// the range the JPEG tables are written for. Chroma is the mean of the 2x2 block a pixel
// belongs to, written to all four pixels: 4:2:0 at full-resolution storage.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D cur_image;

layout(push_constant, std430) uniform Params {
	ivec2 size; // internal size, multiples of 16
	vec2 src_uv_per_px; // internal pixel -> source uv
	float luminance_multiplier; // stored colour * this = linear colour
	float pad0;
	float pad1;
	float pad2;
} params;

shared vec2 chroma[64];

vec3 encode_curve(vec3 c) {
	c = max(c, vec3(0.0));
	return pow(c / (1.0 + c), vec3(1.0 / 2.2));
}

// BT.601 full range (the JPEG/JFIF matrix).
vec3 rgb_to_ycc(vec3 c) {
	return vec3(
		0.299 * c.r + 0.587 * c.g + 0.114 * c.b,
		-0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b,
		0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b);
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	uint local = gl_LocalInvocationIndex;
	vec2 uv = min((vec2(p) + 0.5) * params.src_uv_per_px, vec2(1.0));
	// At internal scale 0.5 one bilinear tap at the centre is the 2x2 box average of the source.
	vec3 linear_rgb = textureLod(source_color, uv, 0.0).rgb * params.luminance_multiplier;
	vec3 ycc = rgb_to_ycc(encode_curve(linear_rgb));
	chroma[local] = ycc.yz;
	barrier();
	// Workgroups are 8-aligned, so the 2x2 quad is inside this group.
	uvec2 l = gl_LocalInvocationID.xy & ~uvec2(1u);
	uint i = l.y * 8u + l.x;
	vec2 c = 0.25 * (chroma[i] + chroma[i + 1u] + chroma[i + 8u] + chroma[i + 9u]);
	if (any(greaterThanEqual(p, params.size))) {
		return;
	}
	imageStore(cur_image, p, vec4(ycc.x * 255.0 - 128.0, c * 255.0, 1.0));
}
