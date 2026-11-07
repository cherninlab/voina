// Opt-in on duplicated stair-hall materials; shared stone defaults stay unchanged.
uniform int stair_art_role = 0; // 1 structural wall, 2 tread/coping
uniform int stair_soot_count = 0;
uniform vec3 stair_soot[4];
uniform vec3 stair_seal_anchor;
uniform vec3 stair_seal_normal;
uniform float stair_seal_length = 0.0;

vec3 stair_surface(vec3 color, vec3 position, vec3 normal, float grain) {
	if (stair_art_role == 0) { return color; }
	float top = smoothstep(0.18, 0.82, normal.y);
	float grey = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(grey), color, 0.65);
	if (stair_art_role == 1) {
		color *= vec3(0.84, 0.90, 0.94) * (1.0 + top * 0.06);
	} else {
		color *= mix(vec3(0.84, 0.89, 0.92), vec3(1.38, 1.40, 1.40), top);
		color *= 1.0 + top * smoothstep(0.54, 0.82, grain) * 0.06;
	}
	for (int i = 0; i < 4; i++) {
		if (i >= stair_soot_count) { break; }
		vec3 delta = position - stair_soot[i];
		float height = delta.y - 0.45;
		float width = 0.24 + max(height, 0.0) * 0.13;
		float smoke = exp(-dot(delta.xz, delta.xz) / (width * width));
		smoke *= smoothstep(-0.1, 0.3, height) * (1.0 - smoothstep(1.1, 2.5, height));
		color *= 1.0 - smoke * 0.23;
	}
	if (stair_art_role == 1 && stair_seal_length > 0.0) {
		vec3 delta = position - stair_seal_anchor;
		float span = 1.0 - smoothstep(stair_seal_length * 0.5 - 0.10, stair_seal_length * 0.5, abs(delta.x));
		span *= 1.0 - smoothstep(0.07, 0.16, abs(dot(delta, stair_seal_normal)));
		span *= smoothstep(0.50, 0.85, dot(normal, stair_seal_normal));
		vec2 cell = vec2((fract(delta.x / 0.44) - 0.5) * 0.44, delta.y);
		float circle = abs(length(cell) - 0.075);
		float stem = max(abs(cell.x) - 0.004, abs(cell.y) - 0.12);
		float border = abs(abs(delta.y) - 0.16);
		float distance_to_cut = min(min(circle, stem), border);
		float mark = 1.0 - smoothstep(0.003, max(0.008, fwidth(distance_to_cut) * 1.3), distance_to_cut);
		color *= 1.0 - mark * span * (0.24 + grain * 0.22);
	}
	return color;
}
