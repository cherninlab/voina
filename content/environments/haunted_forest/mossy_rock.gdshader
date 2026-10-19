shader_type spatial;
// Mossy forest boulders (T-092): the generated schist albedo, triplanar, with moss on top faces.

uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.6, 0.62, 0.63);
uniform vec3 moss_tint : source_color = vec3(0.17, 0.21, 0.13);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(4.0));
	weights /= weights.x + weights.y + weights.z;
	vec3 p = world_position * 0.35;
	vec3 stone = texture(rock, p.zy).rgb * weights.x + texture(rock, p.xz).rgb * weights.y + texture(rock, p.xy).rgb * weights.z;
	float luminance = dot(stone, vec3(0.299, 0.587, 0.114));
	stone = mix(stone, vec3(luminance), 0.6) * tint * 1.3;
	float moss = smoothstep(0.3, 0.75, world_normal.y + sin(world_position.x * 3.1) * sin(world_position.z * 2.7) * 0.18);
	ALBEDO = mix(stone, moss_tint * (0.7 + luminance), moss);
	ROUGHNESS = mix(0.85, 1.0, moss);
	SPECULAR = 0.3;
}
