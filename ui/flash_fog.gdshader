shader_type spatial;
// Light scattered back to the lens by the fog (ui/shading_lighting.gd). The Mobile renderer has no
// volumetric fog, so the environment's depth fog only absorbs: with a black fog colour everything
// fades into black. This full-screen pass adds what the lights put into that fog along each view
// ray, in each light's own colour: the camera lantern (a flash's bright veil right in front of the
// lens, falling off with distance) and the nearest fire lights (a glowing haze ball around every
// torch and grave fire, cut off where a wall stands in front of it).
// The flash integral is taken in u = 1 / t, where the inverse-power falloff is smooth; the fire
// integral is the closed-form "airlight" of a point light: the atan of the ray's closest approach.
// Drawn after every other transparent (render_priority in shading_lighting.gd), so haze also lies
// over foliage, flames and the road overlay; it only adds, so they still show through.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

const int MAX_FIRES = 16;
const int FLASH_STEPS = 12;
const float PHASE = 0.0796; // isotropic scattering, 1 / 4π, in the same units as lit surfaces

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float density = 0.01;
uniform vec3 flash_color = vec3(0.0);
uniform float flash_range = 30.0;
uniform float flash_decay = 2.0;
uniform float flash_cos = 0.26; // cosine of the cone's half angle; -1 is all around
uniform float flash_near = 0.3;
uniform int fire_count = 0;
uniform vec4 fire_position[MAX_FIRES]; // world xyz, range
uniform vec4 fire_color[MAX_FIRES]; // linear colour × energy × strength

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float window(float d, float range) {
	float n = d / range;
	n *= n;
	n = max(1.0 - n * n, 0.0);
	return n * n;
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	vec4 near_point = INV_PROJECTION_MATRIX * vec4(ndc, 1.0, 1.0);
	vec3 ray = normalize(near_point.xyz / near_point.w);
	float dist = 10000.0;
	if (depth > 0.000001) {
		vec4 hit = INV_PROJECTION_MATRIX * vec4(ndc, depth, 1.0);
		dist = length(hit.xyz / hit.w);
	}
	vec3 light = vec3(0.0);

	// Flash: lit from the lens outwards, the light travels out and back through the fog.
	float upto = min(dist, flash_range);
	if (upto > flash_near && dot(flash_color, flash_color) > 0.0) {
		float facing = -ray.z;
		float cone = flash_cos <= -0.99 ? 1.0 : smoothstep(flash_cos, 1.0, facing); // hot centre
		float u_far = 1.0 / upto;
		float u_near = 1.0 / flash_near;
		float du = (u_near - u_far) / float(FLASH_STEPS);
		float sum = 0.0;
		for (int step = 0; step < FLASH_STEPS; step++) {
			float u = u_far + (float(step) + 0.5) * du;
			float t = 1.0 / u;
			// t^-decay dt = u^(decay - 2) du
			sum += pow(u, flash_decay - 2.0) * exp(-2.0 * density * t) * window(t, flash_range);
		}
		light += flash_color * density * cone * sum * du;
	}

	// Fires: inverse-square airlight from the ray's closest approach, clipped to its range and
	// to the first surface the ray hits.
	vec3 origin = INV_VIEW_MATRIX[3].xyz;
	vec3 world_ray = normalize((INV_VIEW_MATRIX * vec4(ray, 0.0)).xyz);
	for (int index = 0; index < MAX_FIRES; index++) {
		if (index >= fire_count) {
			break;
		}
		vec3 offset = fire_position[index].xyz - origin;
		float range = fire_position[index].w;
		float along = dot(offset, world_ray);
		float side = sqrt(max(dot(offset, offset) - along * along, 0.0));
		float h = max(side, 0.25);
		float reach = sqrt(max(range * range - side * side, 0.0));
		float a = max(along - reach, 0.0);
		float b = min(along + reach, dist);
		if (b <= a) {
			continue;
		}
		float airlight = (atan((b - along) / h) - atan((a - along) / h)) / h;
		float travel = max(along, 0.0) + side;
		light += fire_color[index].rgb * density * airlight * window(side, range) * exp(-density * travel);
	}
	ALBEDO = light * PHASE;
}
