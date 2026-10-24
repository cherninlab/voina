shader_type spatial;
// Cobweb alpha card for the web_corner_* and web_sheet_* meshes. No texture: silk threads are
// drawn from the mesh UVs, which are metres (corner webs: UV 0,0 is the anchored apex).
// style 0 (corner): radial threads fanning from the apex, crossed by broken capture threads that
// run straight from radial to radial, plus dust that thickens towards the corner.
// style 1 (sheet): several layers of long, slightly bent strands at random angles over a dusty
// film, like the tangled sheets slung under beams.
// Threads are thinner than a pixel at most distances: coverage is the thread width over the
// pixel footprint, so distant webs fade to a haze instead of shimmering.
// Vertex colour: R = baked AO, G = variation, B = free-edge wear (edges thin out and fray).
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

uniform int style : hint_range(0, 1) = 0;
uniform vec3 silk : source_color = vec3(0.78, 0.76, 0.72);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float thread_width_m = 0.0005;
uniform float radials = 15.0;          // corner: radial threads across the quarter turn
uniform float capture_spacing_m = 0.022;
uniform float strand_density = 1.0;    // sheet: strands per centimetre, roughly
uniform float dust : hint_range(0.0, 1.0) = 0.16;
uniform float seed = 0.0;

float hash1(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Coverage of a thread `distance_m` away, given the pixel footprint in metres.
float thread(float distance_m, float footprint_m) {
	float half_width = max(thread_width_m, footprint_m) * 0.5;
	float edge = clamp(1.0 - (distance_m - half_width) / max(footprint_m, 1e-6), 0.0, 1.0);
	return edge * min(1.0, thread_width_m / max(footprint_m, 1e-6)) * 1.6;
}

float tangle(vec2 p, float footprint, float density, int layers) {
	// Long, slightly bent strands at random angles, each broken into pieces.
	float cover = 0.0;
	vec2 warp = vec2(noise(p * 3.1), noise(p * 3.1 + 7.7)) - 0.5;
	for (int layer = 0; layer < layers; layer++) {
		float l = float(layer);
		float angle = hash1(l * 3.1 + 1.0) * 3.14159;
		vec2 dir = vec2(cos(angle), sin(angle));
		vec2 q = p + warp * 0.05 * (1.0 + l * 0.3);
		float across = dot(q, vec2(-dir.y, dir.x));
		float along = dot(q, dir);
		float spacing = 0.012 / density * (1.0 + hash1(l + 9.0));
		float cell = floor(across / spacing);
		float center = (cell + 0.2 + 0.6 * hash2(vec2(cell, l))) * spacing;
		float present = step(0.45, noise(vec2(along * 6.0, cell * 1.7 + l * 13.0)));
		cover = max(cover, thread(abs(across - center), footprint) * present);
	}
	return cover;
}

float corner_web(vec2 p, float footprint) {
	float r = length(p);
	float angle = atan(max(p.y, 0.0), max(p.x, 1e-5));
	float step_angle = 1.5707963 / radials;
	float k = floor(angle / step_angle);
	float a0 = (k + 0.5 + 0.8 * (hash1(k) - 0.5)) * step_angle;
	float a1 = (k + 1.5 + 0.8 * (hash1(k + 1.0) - 0.5)) * step_angle;
	float am = (k - 0.5 + 0.8 * (hash1(k - 1.0) - 0.5)) * step_angle;
	// Nearest radials either side; some snap part way out.
	float cover = 0.0;
	for (int i = 0; i < 3; i++) {
		float n = k + float(i) - 1.0;
		float a = i == 0 ? am : (i == 1 ? a0 : a1);
		float d = r * abs(sin(angle - a));
		float reach = mix(0.12, 0.6, hash1(n + 40.0));
		float present = hash1(n + 70.0) < 0.6 ? 1.0 : step(r, reach);
		cover = max(cover, thread(d, footprint) * step(0.0, cos(angle - a)) * present);
	}
	// Capture threads: straight chords between the two radials around this point, irregularly
	// spaced and mostly broken in an old web.
	float lo = angle < a0 ? am : a0;
	float hi = angle < a0 ? a0 : a1;
	float bisector = 0.5 * (lo + hi);
	float half_span = 0.5 * (hi - lo);
	float along = r * cos(angle - bisector) / max(cos(half_span), 0.2);
	// Offsets and gaps vary smoothly with angle, so a thread continues across several radials
	// like a spiral before it breaks.
	float spacing = capture_spacing_m;
	float j = floor(along / spacing + 0.5);
	float offset = (noise(vec2(bisector * 2.0, j * 0.77)) - 0.5) * 0.4 * spacing;
	float d = abs(along - j * spacing - offset) * cos(half_span);
	float present = step(0.4, noise(vec2(bisector * 2.5 + 3.0, j * 1.31))) * step(0.04, r);
	cover = max(cover, thread(d, footprint) * present * 0.7);
	// Loose strands and dust gather into the corner.
	cover = max(cover, tangle(p, footprint, 0.6, 4) * smoothstep(0.45, 0.0, r));
	float haze = dust * (0.3 + 0.9 * exp(-r / 0.15)) * (0.4 + noise(p * 22.0));
	return max(cover, haze);
}

float sheet_web(vec2 p, float footprint) {
	float cover = tangle(p, footprint, strand_density, 5);
	float haze = dust * (0.4 + 0.9 * noise(p * 9.0) * noise(p * 2.3 + 3.0));
	return max(cover, haze);
}

void fragment() {
	vec2 p = UV;
	float footprint = max(length(fwidth(p)), 1e-5);
	float cover = style == 0 ? corner_web(p, footprint) : sheet_web(p, footprint);
	float edge = COLOR.b;
	cover *= 1.0 - 0.75 * edge * edge;
	cover *= 0.75 + 0.25 * COLOR.g;
	ALBEDO = silk * mix(1.0, COLOR.r, 0.6);
	ROUGHNESS = 0.7;
	BACKLIGHT = silk * 0.5;
	ALPHA = clamp(cover * opacity, 0.0, 1.0);
}
