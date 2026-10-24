// Baked flagstone modules (T-165, scripts/art/build_flagstones.py). Unlike the world-projected
// dungeon_surface shader this samples the mesh UVs: metres, rotated and offset per stone, so the
// texture changes at every joint and continues across a crack. Vertex COLOR carries data, not
// colour: R = baked AO, G = per-stone variation, B = edge wear (arrises and chips).
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
// 0.5 repeats per metre: 2048 px maps give 1024 px/m, and a 4 m module holds whole repeats.
uniform float repeats_per_metre = 0.5;
uniform vec3 tint : source_color = vec3(0.88, 0.85, 0.80);
uniform vec3 warm : source_color = vec3(1.0, 0.93, 0.84);
uniform vec3 cool : source_color = vec3(0.88, 0.91, 0.94);
uniform float variation = 0.14;
uniform float wear_light = 0.22;
uniform float ao_albedo = 0.25;
uniform float normal_strength = 0.4;
uniform float roughness_min = 0.62;
uniform float grime = 0.15;
uniform bool dirt = false;
#ifdef CLIP
// Convex outline in world x/z: a fragment survives when dot(p.xz, plane.xy) <= plane.z for all planes.
uniform int clip_count = 0;
uniform vec3 clip_planes[12];
#endif
varying vec3 world_position;

float noise3(vec3 p) {
	highp vec3 cell = floor(p);
	highp vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	highp vec4 h = vec4(dot(cell, vec3(1.0, 57.0, 113.0))) + vec4(0.0, 1.0, 57.0, 58.0);
	highp vec4 a = fract(sin(h) * 43758.5453);
	highp vec4 b = fract(sin(h + 113.0) * 43758.5453);
	return mix(mix(mix(a.x, a.y, f.x), mix(a.z, a.w, f.x), f.y),
		mix(mix(b.x, b.y, f.x), mix(b.z, b.w, f.x), f.y), f.z);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
#ifdef CLIP
	for (int i = 0; i < clip_count; i++) {
		if (dot(world_position.xz, clip_planes[i].xy) > clip_planes[i].z) {
			discard;
		}
	}
#endif
	vec2 uv = UV * repeats_per_metre;
	vec3 base = texture(albedo_map, uv).rgb;
	// World-space grime breaks the 4 m repeat without touching the seams.
	float broad = noise3(world_position * 0.21 + vec3(5.1, 0.0, 2.7));
	float fine = noise3(world_position * 1.9 + vec3(2.3, 7.7, 1.1));
	vec3 color;
	if (dirt) {
		color = base * vec3(0.5, 0.43, 0.36) * mix(0.7, 1.05, COLOR.g);
	} else {
		float luminance = dot(base, vec3(0.2126, 0.7152, 0.0722));
		float tone = mix(1.0 - variation, 1.0 + variation, COLOR.g);
		vec3 hue = mix(cool, warm, fract(COLOR.g * 5.37));
		color = mix(vec3(luminance), base, 0.7) * tint * hue * tone;
		color *= 1.0 + wear_light * COLOR.b;
	}
	color *= mix(1.0 - grime, 1.0, broad) * mix(0.93, 1.04, fine);
	// Godot Mobile has no SSAO: the baked AO darkens joints, chips and dirt hollows.
	ALBEDO = color * mix(1.0, COLOR.r, ao_albedo);
	AO = COLOR.r;
	AO_LIGHT_AFFECT = 0.3;
	NORMAL_MAP = texture(normal_map, uv).xyz;
	NORMAL_MAP_DEPTH = normal_strength * (dirt ? 2.0 : 1.0);
	float rough = texture(roughness_map, uv).r;
	ROUGHNESS = dirt ? mix(0.8, 1.0, rough) : mix(roughness_min, 0.98, rough) * mix(1.0, 0.88, COLOR.b);
	SPECULAR = 0.35;
}
