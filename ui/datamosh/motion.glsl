#[compute]
#version 450

// Step 2: one motion vector per 16x16 macroblock (one invocation per macroblock).
// The search is seeded the way a real encoder seeds it from a predicted vector: here the
// prediction is the camera motion, reprojecting the block centre's depth through last frame's
// view-projection. A block-matching search around that seed (luma SAD against last frame's
// source) then finds what moved on its own: players, raiders, swords.
// mv is (current - previous) position in internal pixels: prediction is ref(x - mv).
// mv_error degrades it like a sloppy encoder: some blocks take a neighbour's seed or random
// jitter, re-drawn every frame.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D cur_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D prev_image;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D mv_image;
layout(set = 0, binding = 4, std140) uniform Camera {
	mat4 cam_to_world;
	mat4 prev_view_proj;
	vec4 proj; // P[0][0], P[1][1], P[2][0], P[2][1] of this frame's projection
	vec4 clip; // near, far, has_depth, has_previous
} camera;

layout(push_constant, std430) uniform Params {
	ivec2 size;
	vec2 src_uv_per_px;
	float mv_error;
	uint frame;
	uint intra;
	float pad0;
} params;

const float MV_MAX = 64.0;

uint pcg(uint v) {
	uint s = v * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

float rnd(ivec2 b, uint k) {
	return float(pcg(uint(b.x) + pcg(uint(b.y) + pcg(params.frame * 7u + k)))) / 4294967295.0;
}

// Camera motion of the surface seen at internal pixel `px`, in internal pixels.
vec2 camera_vector(vec2 px) {
	if (camera.clip.w < 0.5) {
		return vec2(0.0);
	}
	vec2 uv = min(px * params.src_uv_per_px, vec2(1.0));
	// Reverse Z: 1 at the near plane, 0 at infinity. No depth: treat as far (pure rotation).
	float d = camera.clip.z > 0.5 ? textureLod(depth_tex, uv, 0.0).r : 0.0;
	float near = camera.clip.x;
	float far = camera.clip.y;
	float z = near * far / (near + d * (far - near));
	vec2 ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
	vec3 view = vec3(z * (ndc.x + camera.proj.z) / camera.proj.x, z * (ndc.y + camera.proj.w) / camera.proj.y, -z);
	vec4 world = camera.cam_to_world * vec4(view, 1.0);
	vec4 prev = camera.prev_view_proj * world;
	if (prev.w <= 0.0) {
		return vec2(0.0);
	}
	vec2 prev_ndc = prev.xy / prev.w;
	vec2 prev_uv = vec2(prev_ndc.x * 0.5 + 0.5, 0.5 - prev_ndc.y * 0.5);
	return px - prev_uv / params.src_uv_per_px;
}

float luma(ivec2 p, bool previous) {
	p = clamp(p, ivec2(0), params.size - 1);
	return previous ? imageLoad(prev_image, p).r : imageLoad(cur_image, p).r;
}

// Mean absolute luma difference of the block against the previous source displaced by mv,
// on every second pixel (64 taps).
float block_cost(ivec2 origin, ivec2 mv) {
	float sum = 0.0;
	for (int y = 0; y < 16; y += 2) {
		for (int x = 0; x < 16; x += 2) {
			ivec2 p = origin + ivec2(x, y);
			sum += abs(luma(p, false) - luma(p - mv, true));
		}
	}
	return sum / 64.0;
}

void main() {
	ivec2 b = ivec2(gl_GlobalInvocationID.xy);
	ivec2 blocks = params.size >> 4;
	if (any(greaterThanEqual(b, blocks))) {
		return;
	}
	if (params.intra != 0u) {
		imageStore(mv_image, b, vec4(0.0, 0.0, 0.0, 1.0));
		return;
	}
	ivec2 origin = b * 16;
	ivec2 seed_block = b;
	if (rnd(b, 0u) < params.mv_error * 0.6) {
		int n = int(rnd(b, 1u) * 4.0);
		seed_block += n == 0 ? ivec2(1, 0) : n == 1 ? ivec2(-1, 0) : n == 2 ? ivec2(0, 1) : ivec2(0, -1);
		seed_block = clamp(seed_block, ivec2(0), blocks - 1);
	}
	vec2 seed = camera_vector(vec2(seed_block * 16) + 8.0);
	ivec2 centre = ivec2(round(seed));
	// Coarse ring around the seed (and the zero vector), then a fine search around the best.
	ivec2 best = centre;
	float best_cost = block_cost(origin, best);
	float zero_cost = block_cost(origin, ivec2(0)) + 0.5;
	if (zero_cost < best_cost) {
		best = ivec2(0);
		best_cost = zero_cost;
	}
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			ivec2 c = centre + ivec2(x, y) * 4;
			// A small pull towards the seed keeps flat areas (sky, plaster) on the camera motion.
			float cost = block_cost(origin, c) + 0.08 * length(vec2(c - centre));
			if (cost < best_cost) {
				best = c;
				best_cost = cost;
			}
		}
	}
	ivec2 coarse = best;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			ivec2 c = coarse + ivec2(x, y);
			float cost = block_cost(origin, c) + 0.08 * length(vec2(c - centre));
			if (cost < best_cost) {
				best = c;
				best_cost = cost;
			}
		}
	}
	vec2 mv = vec2(best);
	if (rnd(b, 2u) < params.mv_error) {
		mv += floor((vec2(rnd(b, 3u), rnd(b, 4u)) - 0.5) * 16.0 * params.mv_error + 0.5);
	}
	mv = clamp(mv, -MV_MAX, MV_MAX);
	imageStore(mv_image, b, vec4(mv, 0.0, 1.0));
}
