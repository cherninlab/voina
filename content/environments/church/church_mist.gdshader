shader_type spatial;
// Low drifting graveyard mist: thin terrain-following layers, softened where they meet stones,
// walls and ground, faded at the region edge and near the camera. Lit, so torches tint it.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert_wrap, specular_disabled, shadows_disabled;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 mist_color : source_color = vec3(0.56, 0.6, 0.64);
uniform float density = 0.35;
uniform float layer = 0.0;
uniform vec4 region = vec4(-23.0, -115.0, 15.0, -84.0);
uniform float edge = 7.0;
uniform float soft = 0.9;
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 drift = vec2(TIME * 0.045, TIME * 0.018) * (1.0 + layer * 0.4);
	float n = noise(p * 0.11 + drift + vec2(layer * 7.3)) * 0.6 + noise(p * 0.31 - drift * 1.7 + vec2(layer * 3.1)) * 0.4;
	n = smoothstep(0.36, 0.9, n);
	float inside = min(min(p.x - region.x, region.z - p.x), min(p.y - region.y, region.w - p.y));
	float fade = smoothstep(0.0, edge, inside + (noise(p * 0.2) - 0.5) * 4.0);
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float behind = clamp((-view.z + VERTEX.z) / soft, 0.0, 1.0);
	// Clear at the feet, thicker with distance; seen from above it must not read as a pond, nor
	// edge-on across the yard as a pale flat floor laid over the dark earth.
	float near = smoothstep(1.0, 10.0, length(VERTEX));
	float steep = abs(normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz).y);
	float grazing = (1.0 - 0.7 * steep) * mix(0.4, 1.0, smoothstep(0.04, 0.3, steep));
	ALBEDO = mist_color;
	ROUGHNESS = 1.0;
	ALPHA = clamp(density * n * fade * behind * near * grazing, 0.0, 1.0);
}
