shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never;

// Overlay pass over a possessed villager. Its skin turns chalky and pale (the body's own texture,
// desaturated with the creases deepened, so it looks gaunt), with darker bruised patches, sunken
// dark eye sockets and a little dried blood down the forearms and shins; the eyes go milky with
// a faint glow that flares during the pounce coil. Over the body it paints ragged peasant clothes:
// a torn linen shirt or smock with sleeves of any length, wool trousers or a dress, a rope belt,
// stains and mud up the legs. Their masks live in the rest (T) pose, carried per vertex in CUSTOM3,
// so they stay on the body however it bends, and their edges are torn by noise. On top
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
uniform float cloth = 0.0;
uniform vec3 shirt_color : source_color = vec3(0.6, 0.55, 0.45);
uniform vec3 lower_color : source_color = vec3(0.34, 0.31, 0.27);
uniform vec3 belt_color : source_color = vec3(0.44, 0.38, 0.28);
uniform vec3 mud_color : source_color = vec3(0.24, 0.18, 0.12);
uniform vec3 stain_color : source_color = vec3(0.16, 0.07, 0.05);
uniform float dress = 0.0; // a dress rather than trousers, with an apron over the skirt
uniform vec3 apron_color : source_color = vec3(0.6, 0.55, 0.45);
uniform float hem = 0.8; // shirt hem height, rest pose (m over the soles)
uniform float sleeve = 0.4; // sleeve reach, shoulder (0) to wrist (1)
uniform float lower_end = 0.4; // trousers or skirt end height
uniform float collar = 1.46; // neckline height at the back
uniform float collar_drop = 0.06; // its dip at the front
uniform float waist = 0.99;
uniform float belt = 1.0;
uniform float tears = 0.2;
uniform float stains = 0.4;
uniform float mud = 0.3;
uniform float cloth_seed = 0.0;
uniform vec2 arm_span = vec2(0.21, 0.71); // shoulder and wrist distance from the middle, rest pose
instance uniform int surface_role = 0; // 0 hair: wounds only, 1 skin, 2 eyes
instance uniform float cut_side = 0.0;

varying vec3 world_pos;
varying vec3 rest; // this vertex in the rest pose
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

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rest = CUSTOM3.xyz;
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
		float worn = 0.0; // how much cloth covers this point
		vec3 fabric = vec3(0.0);
		float wet = 0.0;
		if (cloth > 0.0) {
			vec3 r = rest;
			float ax = abs(r.x);
			bool arm = ax > arm_span.x - 0.01 && r.y > collar - 0.35;
			// Torn edges: every hem wanders by a few centimetres.
			float rag = (noise3(r * 9.0 + cloth_seed) - 0.5) * 0.07 + (noise3(r * 26.0 + cloth_seed * 1.7) - 0.5) * 0.03;
			float neck = ax < 0.1 ? collar - collar_drop * smoothstep(-0.02, 0.09, r.z) * (1.0 - ax / 0.1) : 9.0;
			float sleeve_end = mix(arm_span.x, arm_span.y, sleeve);
			float shirt = step(hem + rag, r.y) * step(r.y, neck + rag * 0.4) * (arm ? step(ax, sleeve_end + rag) : 1.0);
			float lower = arm ? 0.0 : step(r.y, waist + 0.01) * step(lower_end + rag, r.y);
			float region = max(shirt, lower);
			// A few small rents where skin shows through, each with a dark frayed lip.
			float rent = noise3(r * 17.0 + cloth_seed * 3.1) * 0.6 + noise3(r * 45.0 + cloth_seed) * 0.4;
			float cut = 0.86 - tears * 0.3;
			float hole = smoothstep(cut, cut + 0.015, rent);
			float lip = smoothstep(cut - 0.05, cut, rent) * (1.0 - hole);
			worn = region * (1.0 - hole);
			fabric = shirt > 0.5 ? shirt_color : lower_color;
			// Cloth bunches at the knees and elbows, and the shirt shades the trousers under its hem.
			float knee = 1.0 - 0.18 * smoothstep(0.06, 0.0, abs(r.y - 0.52)) * noise3(vec3(r.x * 40.0, r.y * 90.0, r.z * 40.0));
			float elbow = arm ? 1.0 - 0.15 * smoothstep(0.05, 0.0, abs(ax - mix(arm_span.x, arm_span.y, 0.5))) * noise3(r * 80.0) : 1.0;
			float overhang = shirt > 0.5 ? 1.0 : 1.0 - 0.3 * smoothstep(0.05, 0.0, hem + rag - r.y);
			// A dress carries an apron over the front of its skirt.
			if (dress > 0.5 && !arm && r.z > -0.005 + rag * 0.2 && ax < 0.21 && r.y < waist - 0.01 && r.y > lower_end + 0.07 + rag) {
				fabric = apron_color;
			}
			fabric *= knee * elbow * overhang * (1.0 - 0.45 * lip);
			// Weave, hanging folds, a frayed darker edge at each hem and darker stains.
			float weave = 0.84 + 0.16 * noise3(r * 170.0);
			float fold = 0.7 + 0.3 * noise3(vec3(r.x * 28.0, r.y * 4.0, r.z * 28.0) + cloth_seed);
			float frayed = shirt > 0.5 ? 1.0 - smoothstep(0.0, 0.025, r.y - hem - rag) : 1.0 - smoothstep(0.0, 0.025, r.y - lower_end - rag);
			fabric *= weave * fold * (1.0 - 0.35 * frayed);
			float stain = smoothstep(0.6, 0.72, noise3(r * 4.5 + cloth_seed * 5.0)) * stains;
			fabric = mix(fabric, stain_color, stain * 0.75);
			fabric = mix(fabric, mud_color, smoothstep(waist, 0.15, r.y) * 0.3);
			// A rope belt, a thin twisted cord.
			if (belt > 0.5 && !arm && abs(r.y - waist + 0.005) < 0.011) {
				float twist = 0.8 + 0.2 * sin((r.y * 2.0 + atan(r.z, r.x) * 0.35) * 70.0);
				fabric = belt_color * twist * fold;
				worn = 1.0;
			}
			// Under the clothes there is skin, even where the texture paints underwear.
			chalk = mix(chalk, skin_tint * 0.9, 1.0 - skin);
			skin = 1.0;
			// Mud soaked up the legs, over skin and cloth alike: thickest at the feet, patchy above.
			float splash = noise3(r * 13.0 + cloth_seed * 0.7) * 0.6 + noise3(r * 37.0) * 0.4;
			float height = clamp((mud - r.y) / mud, 0.0, 1.0);
			wet = smoothstep(0.4, 0.75, splash * 0.6 + height * 0.8) * step(r.y, mud + 0.1);
		}
		color = mix(chalk, fabric, worn);
		color = mix(color, mud_color * (0.65 + 0.35 * noise3(rest * 40.0)), wet * 0.75);
		alpha = max(skin * 0.96, max(worn, wet)) * possessed;
		roughness = mix(mix(0.78, 0.93, worn), 0.55, wet);
		if (use_normal) {
			// The body's muscles do not show through cloth.
			NORMAL_MAP = mix(texture(skin_normal, UV).rgb, vec3(0.5, 0.5, 1.0), worn);
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
