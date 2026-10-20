shader_type spatial;
// A small live torch flame on an upright, camera-facing quad. Scrolling fractal noise eats into a
// teardrop body so tongues tear off and lick upward; a heat ramp runs from deep red at the ragged
// edges through saturated orange to a yellow core. Premultiplied: it adds light like fire in the
// dark, yet partly covers a bright sky so it stays orange instead of washing out to white.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float heat = 1.0;
instance uniform float seed = 0.0;
uniform float brightness = 1.0;
uniform float cover = 0.55;
uniform float fog_density = 0.0;
// 0 is the eye's deep-red fire; 1 is fire on a flash photo (ui/shading_lighting.gd): the short
// exposure clips the core to yellow-white and loses the dim red edges, so tongues read thinner.
global uniform float flash_grade;
varying float fade;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 3; octave++) {
		value += amplitude * noise(p);
		p = p * 2.07 + vec2(17.1, 3.7);
		amplitude *= 0.5;
	}
	return value / 0.875;
}

void vertex() {
	// Turn about the world up axis only: a flame always rises vertically.
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 side = cross(up, INV_VIEW_MATRIX[2].xyz);
	side = length(side) > 0.001 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(up, 0.0), vec4(cross(side, up), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	fade = exp(-fog_density * length(MODEL_MATRIX[3].xyz - CAMERA_POSITION_WORLD));
}

void fragment() {
	float y = 1.0 - UV.y; // 0 at the pitch head, 1 at the top of the quad
	float t = TIME * 1.15 + seed * 17.0;
	float gust = (noise(vec2(t * 0.5, seed * 3.0)) - 0.5) * 0.16 + (noise(vec2(t * 1.7, seed * 5.0 + 4.0)) - 0.5) * 0.07;
	float warp = fbm(vec2(UV.x * 2.4 + seed, y * 1.6 - t * 2.0));
	float x = UV.x - 0.5 - (gust + (warp - 0.5) * 0.3) * y;
	float tear = fbm(vec2(UV.x * 4.2 + warp * 1.3 - seed, y * 3.0 - t * 3.3));
	float width = 0.4 * pow(max(1.0 - y, 0.0), 0.65) * smoothstep(-0.06, 0.12, y);
	float profile = 1.0 - smoothstep(0.0, 1.0, abs(x) / max(width, 0.001));
	// Zero outside the body, so nothing ever reaches the quad's edges.
	float fire = profile * ((1.2 - y) * (0.8 + heat * 0.2) + 0.12) - tear * (0.34 + y * 0.95);
	fire = clamp(fire * 1.8, 0.0, 1.0);
	vec3 color = mix(vec3(0.5, 0.035, 0.004), vec3(1.0, 0.27, 0.015), smoothstep(0.04, 0.32, fire));
	color = mix(color, vec3(1.0, 0.43, 0.05), smoothstep(0.32, 0.62, fire));
	color = mix(color, vec3(1.0, 0.56, 0.15), smoothstep(0.78, 1.0, fire));
	vec3 shot = mix(vec3(0.85, 0.3, 0.06), vec3(1.0, 0.6, 0.2), smoothstep(0.08, 0.34, fire));
	shot = mix(shot, vec3(1.0, 0.82, 0.48), smoothstep(0.34, 0.62, fire));
	shot = mix(shot, vec3(1.0, 0.96, 0.84), smoothstep(0.66, 0.95, fire));
	color = mix(color, shot, flash_grade);
	float body = smoothstep(0.015 + flash_grade * 0.07, 0.18 + flash_grade * 0.06, fire);
	ALBEDO = color * body * (0.6 + fire * (1.05 + flash_grade * 0.5)) * brightness * heat * fade;
	ALPHA = body * cover * fade;
}
