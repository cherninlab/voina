shader_type spatial;
// Project in metres on the existing UV-less architecture. Timber follows each instance.
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D metallic_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D substrate_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D substrate_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D substrate_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D substrate_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D peel_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D algae_map : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float scale = 0.4;
uniform float aspect = 1.0;
uniform float normal_strength = 0.4;
uniform float wetness = 0.0;
uniform float metallic_amount = 0.0;
uniform float relief_m = 0.018;
uniform float plaster = 0.0;
uniform float algae = 0.0;
uniform float dry_roughness_min = 0.65;
uniform float wet_roughness = 0.23;
uniform bool timber = false;
varying vec2 surface_uv;
varying vec3 surface_normal;
varying vec3 surface_tangent;
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
	surface_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 n = timber ? NORMAL : surface_normal;
	vec3 tangent;
	vec3 dimensions = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	if (timber) {
		// Match the horizontal source grain to each board, upright post or support's long axis.
		tangent = dimensions.x >= max(dimensions.y, dimensions.z) ? vec3(1.0, 0.0, 0.0) : (dimensions.y >= dimensions.z ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
		if (abs(dot(tangent, n)) > 0.9) { tangent = abs(n.y) < 0.7 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0); }
		tangent = normalize(tangent - n * dot(tangent, n));
	} else if (abs(n.y) > 0.7) {
		tangent = vec3(1.0, 0.0, 0.0);
		tangent = normalize(tangent - n * dot(tangent, n));
	} else {
		tangent = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	}
	vec3 bitangent = normalize(cross(n, tangent));
	vec3 position = world_position;
	vec2 offset = vec2(0.0);
	if (timber) {
		position = VERTEX * dimensions;
		offset = fract(MODEL_MATRIX[3].xz * vec2(0.137, 0.219));
		surface_tangent = normalize(mat3(MODEL_MATRIX) * tangent);
	} else {
		surface_tangent = tangent;
	}
	surface_uv = vec2(dot(position, tangent), -dot(position, bitangent)) * scale * vec2(1.0, aspect) + offset;
}

void fragment() {
	vec3 n = normalize(surface_normal);
	vec3 tangent = normalize(surface_tangent - n * dot(surface_tangent, n));
	vec3 bitangent = normalize(cross(n, tangent));
	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - world_position);
	vec2 uv = surface_uv;
	float relief = relief_m * scale * (1.0 - smoothstep(9.0, 24.0, length(VERTEX)));
	// A shallow ray march gives cracks depth at grazing angles; silhouettes stay geometric.
	if (relief > 0.0001) {
		vec2 step_uv = vec2(dot(to_eye, tangent), -dot(to_eye, bitangent)) * relief / max(dot(to_eye, n), 0.3) / 10.0;
		float layer_depth = 0.0;
		for (int i = 0; i < 10; i++) {
			if (layer_depth >= 1.0 - texture(height_map, uv).r) { break; }
			uv -= step_uv;
			layer_depth += 0.1;
		}
	}
	float broad = noise3(world_position * 0.16);
	float stains = noise3(world_position * vec3(0.55, 0.08, 0.55) + vec3(3.7));
	float exposed = 0.0;
	vec2 foundation_uv = surface_uv / (scale * vec2(1.0, aspect)) * vec2(0.22, 0.44);
	if (plaster > 0.0) {
		float peel = texture(peel_map, surface_uv * 0.31).r;
		exposed = smoothstep(0.48, 0.68, peel * 0.5 + broad * 0.5) * plaster;
	}
	vec3 detail = mix(texture(normal_map, uv).xyz, texture(substrate_normal, foundation_uv).xyz, exposed) * 2.0 - 1.0;
	detail.xy *= normal_strength;
	detail.z = sqrt(max(1.0 - dot(detail.xy, detail.xy), 0.01));
	vec3 bent = normalize(tangent * detail.x + bitangent * detail.y + n * max(detail.z, 0.15));
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	vec3 color = mix(texture(albedo_map, uv).rgb, texture(substrate_albedo, foundation_uv).rgb * vec3(0.7, 0.67, 0.6), exposed);
	color *= tint * COLOR.rgb * mix(0.65, 1.05, broad);
	color *= mix(vec3(0.65, 0.7, 0.62), vec3(1.0), smoothstep(0.25, 0.65, stains));
	float coverage = texture(wet_map, surface_uv * 0.23).r;
	float lower = 1.0 - smoothstep(-40.0, -24.0, world_position.y);
	float growth = smoothstep(0.3, 0.7, texture(algae_map, surface_uv * 0.34).r * stains) * lower * algae;
	color = mix(color, color * vec3(0.27, 0.45, 0.22), growth);
	float wet = smoothstep(0.32, 0.75, coverage * 0.6 + stains * 0.4) * wetness * mix(0.65, 1.0, lower);
	ALBEDO = mix(color, color * vec3(0.5, 0.56, 0.52), wet);
	float dry = mix(texture(roughness_map, uv).r, texture(substrate_roughness, foundation_uv).r, exposed);
	ROUGHNESS = mix(clamp(dry, dry_roughness_min, 0.98), wet_roughness, wet);
	AO = mix(1.0, mix(texture(ao_map, uv).r, texture(substrate_ao, foundation_uv).r, exposed), 0.7);
	AO_LIGHT_AFFECT = 0.15;
	METALLIC = texture(metallic_map, uv).r * metallic_amount;
	SPECULAR = 0.35;
}
