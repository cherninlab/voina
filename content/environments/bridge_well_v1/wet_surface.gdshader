shader_type spatial;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D wet_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D algae_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_map : filter_linear_mipmap, repeat_enable;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.45;
uniform bool height_driven_normal = true;
uniform float height_gradient_gain : hint_range(0.0, 8.0) = 3.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.8;
uniform float algae_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 tile_scale = vec2(1.0);
uniform vec2 tile_offset = vec2(0.0);
uniform vec2 coverage_scale = vec2(0.7);

void fragment() {
	vec2 surface_uv = UV * tile_scale + tile_offset;
	float coverage = textureLod(wet_map, surface_uv * coverage_scale, 3.0).r;
	float wet = (0.2 + 0.8 * coverage) * wetness;
	float algae = texture(algae_map, surface_uv * coverage_scale + vec2(0.23, 0.41)).r * algae_amount;
	vec3 base = texture(albedo_map, surface_uv).rgb;
	base = mix(base, base * vec3(0.75, 0.79, 0.76), wet);
	ALBEDO = mix(base, base * vec3(0.57, 0.72, 0.39), algae);
	// Native roughness is approximate; dry crevices must not become polished grooves.
	float dry_roughness = clamp(texture(roughness_map, surface_uv).r, 0.68, 0.95);
	ROUGHNESS = mix(dry_roughness, 0.16, wet);
	METALLIC = 0.0;
	NORMAL_MAP = texture(normal_map, surface_uv).rgb;
	if (height_driven_normal) {
		vec2 step_uv = 1.0 / vec2(textureSize(height_map, 0));
		float dx = texture(height_map, surface_uv + vec2(step_uv.x, 0.0)).r
			- texture(height_map, surface_uv - vec2(step_uv.x, 0.0)).r;
		float dy = texture(height_map, surface_uv + vec2(0.0, step_uv.y)).r
			- texture(height_map, surface_uv - vec2(0.0, step_uv.y)).r;
		vec3 height_normal = normalize(vec3(-dx * height_gradient_gain, dy * height_gradient_gain, 1.0));
		NORMAL_MAP = height_normal * 0.5 + 0.5;
	}
	NORMAL_MAP_DEPTH = normal_strength;
	AO = texture(ao_map, surface_uv).r;
	AO_LIGHT_AFFECT = 0.0;
}
