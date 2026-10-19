shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never;

// Overlay pass over a possessed villager. Its skin turns chalky and pale (the body's own texture,
// desaturated with the creases deepened, so it looks gaunt), with darker bruised patches, sunken
// dark eye sockets and a little dried blood down the forearms and shins; the eyes go milky with
// a faint glow that flares during the pounce coil. Clothes and hair keep their colours. On top
// sit up to six exaggerated wounds, each the strip of skin within a band of the blade's plane,
// tapered along the blade's travel, with blood running down from it under gravity. Positions
// are world space, refreshed from bones. A bisected half (cut_side +-1) shows only its own side.
uniform vec3 blood : source_color = vec3(0.3, 0.012, 0.01); // HitEffects.BLOOD
uniform int wound_count = 0;
uniform vec3 wound_center[6];
uniform vec3 wound_normal[6];
uniform vec3 wound_travel[6];
uniform float wound_age[6]; // seconds since the hit

uniform float possessed = 0.0;
uniform sampler2D skin_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform vec3 skin_tint : source_color = vec3(0.8, 0.79, 0.76);
uniform float bruise_amount = 0.5;
uniform float bruise_seed = 0.0;
uniform vec2 socket_a = vec2(0.139, 0.177);
uniform vec2 socket_b = vec2(0.235, 0.177);
uniform vec2 socket_size = vec2(0.032, 0.022);
uniform float streak_amount = 0.0;
uniform vec3 streak_origin[4]; // forearms and shins: bone origin, length axis, a side axis, length
uniform vec3 streak_axis[4];
uniform vec3 streak_side[4];
uniform float streak_length[4];
uniform vec3 eye_glow : source_color = vec3(0.95, 0.86, 0.5);
uniform float glow_strength = 0.5;
instance uniform int surface_role = 0; // 0 hair: wounds only, 1 skin, 2 eyes
instance uniform float cut_side = 0.0;

varying vec3 world_pos;
varying vec4 limb; // along the nearest limb (0..1), direction around it (cos, sin), found
varying float limb_index;

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	limb = vec4(0.0);
	limb_index = 0.0;
	if (surface_role == 1 && streak_amount > 0.0) {
		float best = 0.11;
		for (int i = 0; i < 4; i++) {
			vec3 rel = world_pos - streak_origin[i];
			float along = dot(rel, streak_axis[i]);
			float t = along / max(streak_length[i], 0.01);
			vec3 radial = rel - streak_axis[i] * along;
			float r = length(radial);
			if (t > -0.05 && t < 1.05 && r < best && r > 0.0001) {
				best = r;
				vec3 other = cross(streak_axis[i], streak_side[i]);
				limb = vec4(t, dot(radial, streak_side[i]) / r, dot(radial, other) / r, 1.0);
				limb_index = float(i);
			}
		}
	}
}

void fragment() {
	if (cut_side != 0.0 && UV2.x * cut_side <= 0.0) {
		discard;
	}
	vec3 color = blood;
	float alpha = 0.0;
	float wetness = 0.0;
	float roughness = 0.7;
	vec3 emission = vec3(0.0);
	if (possessed > 0.0 && surface_role == 1) {
		vec3 base = texture(skin_albedo, UV).rgb;
		// Skin is the warm part of the texture; the clothes are grey.
		float skin = smoothstep(0.05, 0.14, base.r - base.b);
		// Luminance in linear space: about 0.24 on the texture's skin.
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		float shade = clamp(pow(lum / 0.24, 1.3), 0.25, 1.2);
		vec3 chalk = skin_tint * shade;
		// Bruised, dirty patches.
		vec2 p = UV * 7.0 + vec2(bruise_seed, bruise_seed * 0.7);
		float n = noise2(p) * 0.55 + noise2(p * 2.3 + 4.1) * 0.3 + noise2(p * 5.9 + 9.7) * 0.15;
		float bruise = smoothstep(0.52, 0.8, n) * bruise_amount;
		chalk = mix(chalk, chalk * vec3(0.5, 0.45, 0.5), bruise);
		// Sunken, dark eye sockets.
		vec2 da = (UV - socket_a) / socket_size;
		vec2 db = (UV - socket_b) / socket_size;
		float socket = 1.0 - smoothstep(0.35, 1.0, min(length(da), length(db)));
		chalk = mix(chalk, vec3(0.07, 0.05, 0.06), socket * 0.85);
		// A few dried streaks running down the limb from somewhere along it.
		if (limb.w > 0.5) {
			float around = atan(limb.z, limb.y) / 6.2832 + 0.5;
			float column = around * 16.0 + limb_index * 5.3;
			float id = floor(column);
			float across = abs(fract(column) - 0.5);
			float start = 0.1 + 0.55 * hash(id * 2.3 + bruise_seed);
			float len = 0.15 + 0.4 * hash(id * 1.7 + 3.0 + bruise_seed);
			float u = (limb.x - start) / len;
			float width = 0.22 * (1.0 - 0.7 * clamp(u, 0.0, 1.0));
			float streak = step(hash(id + bruise_seed * 3.1), streak_amount) * step(0.0, u) * (1.0 - smoothstep(0.85, 1.0, u)) * (1.0 - smoothstep(width * 0.6, width, across));
			chalk = mix(chalk, vec3(0.075, 0.03, 0.022), streak * 0.7);
		}
		color = chalk;
		alpha = skin * possessed * 0.96;
		roughness = 0.78;
		if (use_normal) {
			NORMAL_MAP = texture(skin_normal, UV).rgb;
		}
	} else if (possessed > 0.0 && surface_role == 2) {
		// Milky irises with a pinprick pupil in a dull, greyed eye, glowing faintly.
		float r = length(UV - vec2(0.5));
		float iris = 1.0 - smoothstep(0.095, 0.12, r);
		float pupil = 1.0 - smoothstep(0.018, 0.03, r);
		vec3 sclera = vec3(0.36, 0.34, 0.29);
		color = mix(sclera, vec3(0.8, 0.82, 0.8), iris);
		color = mix(color, vec3(0.04), pupil * 0.85);
		emission = eye_glow * glow_strength * (0.25 + iris * (1.0 - pupil));
		alpha = possessed;
		roughness = 0.25;
	}
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
	ROUGHNESS = mix(roughness, 0.12, wetness);
	SPECULAR = mix(0.3, 0.7, wetness);
	ALBEDO = color;
	EMISSION = emission * (1.0 - wetness);
	ALPHA = alpha;
}
