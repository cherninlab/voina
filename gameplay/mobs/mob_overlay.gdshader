shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

// Overlay pass over a raider: the state tint, a white flash on hit, and up to MAX_WOUNDS
// exaggerated slash lines. Each wound is the strip of skin within a band of the blade's plane,
// tapered along the blade's travel. Positions are world space, refreshed from bones every frame.
const int MAX_WOUNDS = 6;
uniform vec4 tint : source_color = vec4(0.85, 0.12, 0.12, 0.25);
uniform float flash = 0.0;
uniform int wound_count = 0;
uniform vec3 wound_center[6];
uniform vec3 wound_normal[6];
uniform vec3 wound_travel[6];
uniform float wound_age[6]; // seconds since the hit
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 color = tint.rgb;
	float alpha = tint.a;
	for (int i = 0; i < MAX_WOUNDS; i++) {
		if (i >= wound_count) {
			break;
		}
		vec3 rel = world_pos - wound_center[i];
		vec3 n = wound_normal[i];
		vec3 t = wound_travel[i];
		float d = abs(dot(rel, n));
		// From just before the contact to well past it along the travel; pointed at both ends.
		float u = (dot(rel, t) + 0.22) / 0.82;
		float across = abs(dot(rel, cross(n, t)));
		if (u <= 0.0 || u >= 1.0 || across > 0.5) {
			continue;
		}
		float age = wound_age[i];
		// The gash opens fast and then stays wide.
		float open = 0.35 + 0.65 * smoothstep(0.0, 0.08, age);
		float width = 0.065 * open * pow(sin(3.14159 * u), 0.6);
		float smear = width * 2.2;
		if (d < smear) {
			float band = 1.0 - smoothstep(width * 0.85, width, d);
			float core = 1.0 - smoothstep(width * 0.25, width * 0.45, d);
			vec3 gash = mix(vec3(0.95, 0.03, 0.02), vec3(0.18, 0.0, 0.0), core);
			// Fresh cuts flare hot before settling into red.
			gash = mix(gash, vec3(1.0, 0.85, 0.7), (1.0 - smoothstep(0.0, 0.12, age)) * (1.0 - core));
			float halo = (1.0 - smoothstep(width, smear, d)) * 0.55;
			color = mix(mix(color, vec3(0.5, 0.0, 0.0), halo), gash, band);
			alpha = max(alpha, max(band, halo));
		}
	}
	color = mix(color, vec3(1.0), flash);
	alpha = max(alpha, flash * 0.85);
	ALBEDO = color;
	ALPHA = alpha;
}
