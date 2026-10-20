// The hooded cultist's robe shaped round the legs (T-110), shared by the robe's own shader
// (robe_push.gdshader) and the cut shader on a bisected half (gameplay/mobs/mob_cut.gdshader).
// RobeCloth.Push writes the ends, in the garment mesh's space (the skeleton's, Y up), each frame:
// thighs and calves left then right, then each forearm running on over the hand. VERTEX is already
// skinned when this runs.
//
// Standing (tent > 0.5) the robe is not simulated. Each skirt vertex is moved out, in its own
// direction from the hips, to the farthest point of the legs at or above its height plus a margin,
// sloping in a little as it falls: the cloth hangs from a forward knee and stretches straight
// between two legs, like a tent, and a leg can never get outside it. A corpse or a cut half
// (tent 0) drapes on its spring bones, and its vertices are only pushed out of the leg and hand
// capsules. Every end zero (a mesh that is not the robe): nothing moves.
instance uniform vec3 thigh_l;
instance uniform vec3 knee_l;
instance uniform vec3 ankle_l;
instance uniform vec3 thigh_r;
instance uniform vec3 knee_r;
instance uniform vec3 ankle_r;
instance uniform vec3 elbow_l;
instance uniform vec3 hand_l;
instance uniform vec3 elbow_r;
instance uniform vec3 hand_r;
instance uniform float tent = 0.0;

const float THIGH_REACH = 0.12; // the thigh's mesh from its bone, plus the cloth (m)
const float CALF_REACH = 0.1; // the kneecap stands out at the top of the calf
const float HAND_REACH = 0.07;
const float TENT_MARGIN = 0.045; // how far outside the legs the tent stands (m)
const float TENT_SLOPE = 0.12; // inward per metre the cloth falls below what holds it out
const float TENT_START = 0.05; // how far below the hips the tent reaches full strength (m)

// How far out along a horizontal direction a leg segment holds the cloth at a height: the farthest
// point of the part of the segment at or above that height, less the slope it falls from there.
float tent_reach(vec3 a, vec3 b, float reach, vec2 center, vec2 direction, float height) {
	float best = -1.0;
	if (a.y >= height) {
		best = max(best, dot(a.xz - center, direction) - TENT_SLOPE * (a.y - height));
	}
	if (b.y >= height) {
		best = max(best, dot(b.xz - center, direction) - TENT_SLOPE * (b.y - height));
	}
	if ((a.y - height) * (b.y - height) < 0.0) {
		vec3 crossing = mix(a, b, (height - a.y) / (b.y - a.y));
		best = max(best, dot(crossing.xz - center, direction));
	}
	// A slanting leg cuts a wider section through the height than an upright one.
	float upright = max(abs(normalize(b - a).y), 0.5);
	return best < 0.0 ? -1.0 : best + reach / upright + TENT_MARGIN;
}

vec3 robe_out_of(vec3 point, vec3 a, vec3 b, float radius) {
	vec3 along = b - a;
	float t = clamp(dot(point - a, along) / max(dot(along, along), 1e-6), 0.0, 1.0);
	vec3 nearest = a + along * t;
	vec3 away = point - nearest;
	float distance = length(away);
	if (distance >= radius) {
		return point;
	}
	vec3 direction = distance > 1e-4 ? away / distance : normalize(vec3(point.x, 0.0, point.z) + vec3(1e-4, 0.0, 0.0));
	return nearest + direction * radius;
}

bool robe_active() {
	return distance(thigh_l, knee_l) > 0.01;
}

vec3 robe_shape(vec3 point) {
	if (!robe_active()) {
		return point;
	}
	if (tent > 0.5) {
		vec2 center = (thigh_l.xz + thigh_r.xz) * 0.5;
		float hips = (thigh_l.y + thigh_r.y) * 0.5;
		float strength = clamp((hips - point.y) / TENT_START, 0.0, 1.0);
		vec2 offset = point.xz - center;
		float radius = length(offset);
		if (strength > 0.0 && radius > 1e-4) {
			vec2 direction = offset / radius;
			float reach = max(max(tent_reach(thigh_l, knee_l, THIGH_REACH, center, direction, point.y), tent_reach(knee_l, ankle_l, CALF_REACH, center, direction, point.y)),
					max(tent_reach(thigh_r, knee_r, THIGH_REACH, center, direction, point.y), tent_reach(knee_r, ankle_r, CALF_REACH, center, direction, point.y)));
			// A soft maximum, so the cloth lifts off its hanging shape without a crease.
			float blend = max(0.06 - abs(reach - radius), 0.0) / 0.06;
			float wanted = max(reach, radius) + blend * blend * 0.06 * 0.25;
			point.xz = center + direction * mix(radius, wanted, strength);
		}
	} else {
		for (int pass = 0; pass < 2; pass++) {
			point = robe_out_of(point, thigh_l, knee_l, THIGH_REACH);
			point = robe_out_of(point, knee_l, ankle_l, CALF_REACH);
			point = robe_out_of(point, thigh_r, knee_r, THIGH_REACH);
			point = robe_out_of(point, knee_r, ankle_r, CALF_REACH);
		}
	}
	// A swinging hand presses into the cloth instead of through it.
	point = robe_out_of(point, elbow_l, hand_l, HAND_REACH);
	point = robe_out_of(point, elbow_r, hand_r, HAND_REACH);
	return point;
}
