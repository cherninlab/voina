shader_type spatial;
// A thin wisp of soot above a torch (GPUParticles3D draw pass). Lit, so torchlight warms its base.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

varying float puff_seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	mat4 facing = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat4 size = mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * facing * size;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	puff_seed = INSTANCE_CUSTOM.y * 37.0 + float(INSTANCE_ID) * 3.1;
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float wisp = noise(UV * 3.2 + vec2(puff_seed, TIME * 0.2)) * 0.65 + noise(UV * 7.0 - vec2(TIME * 0.3, puff_seed)) * 0.35;
	ALBEDO = vec3(0.13, 0.125, 0.12);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = (1.0 - smoothstep(0.15, 1.0, r)) * smoothstep(0.25, 0.75, wisp) * COLOR.a;
}
