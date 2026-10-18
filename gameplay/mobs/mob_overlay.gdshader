shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never;

// Overlay pass over a raider: the state tint and up to six exaggerated wounds. Each wound is
// the strip of skin within a band of the blade's plane, tapered along the blade's travel, with
// blood running down from it under gravity. Positions are world space, refreshed from bones.
uniform vec4 tint : source_color = vec4(0.85, 0.12, 0.12, 0.25);
uniform vec3 blood : source_color = vec3(0.3, 0.012, 0.01); // HitEffects.BLOOD
uniform int wound_count = 0;
uniform vec3 wound_center[6];
uniform vec3 wound_normal[6];
uniform vec3 wound_travel[6];
uniform float wound_age[6]; // seconds since the hit
varying vec3 world_pos;

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 color = tint.rgb;
	float alpha = tint.a;
	float wetness = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= wound_count) {
			break;
		}
		vec3 rel = world_pos - wound_center[i];
		vec3 n = wound_normal[i];
		vec3 t = wound_travel[i];
		float signed_d = dot(rel, n);
		float d = abs(signed_d);
		float a = dot(rel, t);
		// From just before the contact to well past it along the travel; pointed at both ends.
		float u = (a + 0.22) / 0.82;
		float across = abs(dot(rel, cross(n, t)));
		if (u <= 0.0 || u >= 1.0 || across > 0.5) {
			continue;
		}
		float age = wound_age[i];
		float open = 0.4 + 0.6 * smoothstep(0.0, 0.1, age);
		// Torn rather than ruled: the width wanders along the cut.
		float k = a / 0.035 + float(i) * 11.0;
		float ragged = mix(hash(floor(k)), hash(floor(k) + 1.0), smoothstep(0.0, 1.0, fract(k)));
		float width = 0.06 * open * pow(sin(3.14159 * u), 0.6) * (0.6 + 0.7 * ragged);
		// Blood runs down from the gash: thin rivulets in columns along it, growing for a few seconds.
		float drip = 0.0;
		if (abs(n.y) > 0.2) {
			float below = -signed_d / n.y; // height from here up to the cut's plane
			float column = floor(a / 0.022);
			float in_column = abs(fract(a / 0.022) - 0.5);
			float drip_len = (0.06 + 0.3 * hash(column + float(i) * 17.0)) * smoothstep(0.0, 3.0, age);
			float thick = 0.32 - 0.22 * clamp(below / max(drip_len, 0.001), 0.0, 1.0);
			if (below > 0.0 && below < drip_len && in_column < thick && hash(column * 3.7 + float(i)) > 0.35) {
				drip = 1.0 - smoothstep(drip_len * 0.8, drip_len, below);
			}
		}
		// Soft lips that blend into the skin; the opening darkens toward its centre. No rim:
		// one blood colour, lit and wet, with only depth and coverage varying.
		float band = 1.0 - smoothstep(width * 0.55, width * 1.15, d);
		float core = 1.0 - smoothstep(0.0, width * 0.5, d);
		float smear = (1.0 - smoothstep(width, width * 2.4, d)) * 0.35;
		float cover = max(band, max(smear, drip * 0.85));
		vec3 gash = mix(blood, blood * 0.15, core);
		color = mix(color, gash, cover);
		alpha = max(alpha, cover);
		wetness = max(wetness, cover);
	}
	ROUGHNESS = mix(0.7, 0.12, wetness);
	SPECULAR = mix(0.3, 0.7, wetness);
	ALBEDO = color;
	ALPHA = alpha;
}
