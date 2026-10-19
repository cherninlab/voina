shader_type spatial;
// Open grave: a flat quad that ray-marches an imaginary earthen box below it, darkening with
// depth, so the pit reads as a hole without cutting the terrain mesh.
uniform sampler2D earth_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 half_size = vec3(0.45, 1.3, 0.98);
varying vec3 local_pos;
varying vec3 local_camera;

void vertex() {
	local_pos = VERTEX;
	local_camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	vec3 d = normalize(local_pos - local_camera);
	d.y = min(d.y, -0.002);
	d.x = abs(d.x) < 0.0001 ? 0.0001 : d.x;
	d.z = abs(d.z) < 0.0001 ? 0.0001 : d.z;
	vec3 o = vec3(local_pos.x, 0.0, local_pos.z);
	float tx = (sign(d.x) * half_size.x - o.x) / d.x;
	float tz = (sign(d.z) * half_size.z - o.z) / d.z;
	float ty = (-half_size.y - o.y) / d.y;
	float t = min(min(tx, tz), ty);
	vec3 h = o + d * t;
	vec2 uv = ty <= min(tx, tz) ? h.xz : (tx < tz ? h.zy : h.xy);
	vec3 earth = texture(earth_map, uv * 0.8).rgb * vec3(0.3, 0.25, 0.2);
	float depth = -h.y;
	ALBEDO = earth * exp(-depth * 2.4) * (ty <= min(tx, tz) ? 0.55 : 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
