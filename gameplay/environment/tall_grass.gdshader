shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
// Long Grass blades: one clump mesh, instanced. UV.y runs 0 at the root to 1 at the tip; the
// instance colour (MultiMesh) varies the shade per clump.
// Wind: broad gusts roll across the field along wind_dir (the same bands as the pines in
// horizon_pines.gdshader), plus a faint idle flutter. Everything is per clump and per vertex
// arithmetic: no textures, no extra passes.
uniform vec3 root_color : source_color = vec3(0.05, 0.08, 0.06);
uniform vec3 tip_color : source_color = vec3(0.32, 0.4, 0.33);
uniform float wind = 0.18; // tip lean in a gust, metres
uniform vec2 wind_dir = vec2(0.0, -1.0);
uniform float wind_speed = 4.0; // gust travel, metres per second
uniform float gust_size = 18.0; // metres between gust fronts

varying float height;
varying float gust;

void vertex() {
	height = UV.y;
	// One phase per clump (its origin), so a clump bends as one.
	vec2 at = MODEL_MATRIX[3].xz;
	float front = (dot(at, wind_dir) - TIME * wind_speed) / gust_size;
	gust = pow(0.5 + 0.5 * sin(front * 6.2832), 3.0);
	float flutter = sin(TIME * 2.3 + at.x * 0.9 + at.y * 0.6) * 0.18;
	vec3 lean = vec3(wind_dir.x, 0.0, wind_dir.y) * (0.2 + gust) + vec3(flutter, 0.0, flutter * 0.6);
	// World lean into the clump's own (yawed, stretched) frame; the tip moves most.
	mat3 basis = mat3(MODEL_MATRIX);
	float width = dot(basis[0], basis[0]);
	VERTEX.xz += (transpose(basis) * lean).xz / width * wind * UV.y * UV.y;
	// Blades lit as if facing up: a field reads as one soft surface, not flickering cards.
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// Tips bent by a gust catch a little more moonlight, so the wave reads at night.
	ALBEDO = mix(root_color, tip_color, height) * COLOR.rgb * (1.0 + 0.3 * gust * height);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.12);
}
