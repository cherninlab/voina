#[compute]
#version 450

// Steps 3-6 for one 8x8 transform block per workgroup (one invocation per pixel):
//   P  = ref(x - mv)                      motion-compensated prediction (0 on I-frames)
//   R  = (cur - P) * residual_gain        residual; gain < 1 starves it: the datamosh smear
//   C  = DCT(R), C^ = round(C / (Q s)) Q s  orthonormal 8x8 DCT-II, JPEG tables, libjpeg scale
//   out = clamp(P + IDCT(C^))             the reconstruction, the next frame's reference
// The separable transform runs row/column passes in shared memory, so the whole
// encode + decode of a block is one dispatch.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D cur_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D ref_prev;
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D mv_image;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D ref_next;
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D residual_image;

layout(push_constant, std430) uniform Params {
	ivec2 size;
	float q_scale; // libjpeg quality -> table multiplier
	float residual_gain;
	uint intra;
	float pad0;
	float pad1;
	float pad2;
} params;

// JPEG Annex K.1 / K.2, row-major: index = v * 8 + u.
const float Q_LUMA[64] = float[64](
	16.0, 11.0, 10.0, 16.0, 24.0, 40.0, 51.0, 61.0,
	12.0, 12.0, 14.0, 19.0, 26.0, 58.0, 60.0, 55.0,
	14.0, 13.0, 16.0, 24.0, 40.0, 57.0, 69.0, 56.0,
	14.0, 17.0, 22.0, 29.0, 51.0, 87.0, 80.0, 62.0,
	18.0, 22.0, 37.0, 56.0, 68.0, 109.0, 103.0, 77.0,
	24.0, 35.0, 55.0, 64.0, 81.0, 104.0, 113.0, 92.0,
	49.0, 64.0, 78.0, 87.0, 103.0, 121.0, 120.0, 101.0,
	72.0, 92.0, 95.0, 98.0, 112.0, 100.0, 103.0, 99.0);
const float Q_CHROMA[64] = float[64](
	17.0, 18.0, 24.0, 47.0, 99.0, 99.0, 99.0, 99.0,
	18.0, 21.0, 26.0, 66.0, 99.0, 99.0, 99.0, 99.0,
	24.0, 26.0, 56.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	47.0, 66.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0);

shared float basis[64]; // B[k * 8 + n] = c(k) cos((2n + 1) k pi / 16)
shared vec3 a[64];
shared vec3 b[64];

vec3 predict(ivec2 p) {
	if (params.intra != 0u) {
		return vec3(0.0);
	}
	vec2 mv = imageLoad(mv_image, p >> 4).xy;
	vec2 s = vec2(p) - mv;
	vec2 f = floor(s);
	ivec2 i = ivec2(f);
	// A half-pixel component averages the two integer taps either side of it.
	ivec2 h = ivec2(step(0.25, s - f));
	ivec2 hi = params.size - 1;
	vec3 t0 = imageLoad(ref_prev, clamp(i, ivec2(0), hi)).rgb;
	vec3 t1 = imageLoad(ref_prev, clamp(i + ivec2(h.x, 0), ivec2(0), hi)).rgb;
	vec3 t2 = imageLoad(ref_prev, clamp(i + ivec2(0, h.y), ivec2(0), hi)).rgb;
	vec3 t3 = imageLoad(ref_prev, clamp(i + h, ivec2(0), hi)).rgb;
	return 0.25 * (t0 + t1 + t2 + t3);
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	int x = int(gl_LocalInvocationID.x);
	int y = int(gl_LocalInvocationID.y);
	int i = y * 8 + x;
	// This thread's basis entry: k = y, n = x.
	basis[i] = (y == 0 ? sqrt(0.125) : 0.5) * cos(float((2 * x + 1) * y) * 3.14159265358979 / 16.0);

	vec3 prediction = predict(p);
	vec3 residual = imageLoad(cur_image, p).rgb - prediction;
	residual *= params.intra != 0u ? 1.0 : params.residual_gain;
	imageStore(residual_image, p, vec4(residual, 1.0));
	a[i] = residual;
	barrier();

	// Forward rows: b[y][k] = sum_n B[k][n] a[y][n], with k = x.
	vec3 acc = vec3(0.0);
	for (int n = 0; n < 8; n++) {
		acc += basis[x * 8 + n] * a[y * 8 + n];
	}
	b[i] = acc;
	barrier();

	// Forward columns: C[v][u] = sum_n B[v][n] b[n][u], with v = y, u = x. Then quantize.
	acc = vec3(0.0);
	for (int n = 0; n < 8; n++) {
		acc += basis[y * 8 + n] * b[n * 8 + x];
	}
	vec3 q = max(vec3(Q_LUMA[i], Q_CHROMA[i], Q_CHROMA[i]) * params.q_scale, vec3(1e-4));
	a[i] = sign(acc) * floor(abs(acc) / q + 0.5) * q;
	barrier();

	// Inverse columns: b[n][u] = sum_v B[v][n] C^[v][u], with n = y.
	acc = vec3(0.0);
	for (int k = 0; k < 8; k++) {
		acc += basis[k * 8 + y] * a[k * 8 + x];
	}
	b[i] = acc;
	barrier();

	// Inverse rows: R^[y][n] = sum_k B[k][n] b[y][k], with n = x.
	acc = vec3(0.0);
	for (int k = 0; k < 8; k++) {
		acc += basis[k * 8 + x] * b[y * 8 + k];
	}
	imageStore(ref_next, p, vec4(clamp(prediction + acc, vec3(-128.0), vec3(127.5)), 1.0));
}
