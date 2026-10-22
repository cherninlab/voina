shader_type sky;
// Long Grass night sky: the village's storm panorama (content/environments/grim), darkened and
// cooled, with a procedural full moon whose light catches the nearby cloud edges.
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 moon_dir = vec3(0.0, 0.5, -0.85); // unit vector toward the moon
uniform float moon_radius = 0.038; // radians
uniform float darkness = 0.17;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec2 uv = SKY_COORDS;
	uv.x = fract(uv.x + TIME * 0.00008);
	// Same seam and pole handling as the village's storm sky.
	vec3 base = textureLod(panorama, uv, 0.0).rgb;
	vec3 opposite = textureLod(panorama, vec2(1.0 - uv.x, uv.y), 0.0).rgb;
	vec3 clouds = mix((base + opposite) * 0.5, base, smoothstep(0.0, 0.025, min(uv.x, 1.0 - uv.x)));
	clouds = mix(vec3(0.02, 0.025, 0.035), clouds, smoothstep(0.0, 0.07, uv.y));
	float lum = dot(clouds, vec3(0.3, 0.55, 0.15));
	vec3 c = mix(vec3(lum), clouds, 0.6) * vec3(0.75, 0.85, 1.05) * darkness;
	vec3 d = normalize(EYEDIR);
	vec3 m = normalize(moon_dir);
	float angle = acos(clamp(dot(d, m), -1.0, 1.0));
	// Moonlit cloud rims and a wide, faint halo.
	float glow = exp(-angle / (moon_radius * 3.0));
	c += clouds * glow * 0.7 + vec3(0.6, 0.68, 0.8) * exp(-angle / (moon_radius * 10.0)) * 0.035;
	if (angle < moon_radius) {
		// Disc coordinates for limb darkening and soft grey maria.
		vec3 side = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
		vec3 up = cross(side, m);
		vec2 p = vec2(dot(d, side), dot(d, up)) / moon_radius;
		float r = length(p);
		float maria = smoothstep(0.45, 0.75, noise(p * 2.4 + 3.0)) * 0.35 + noise(p * 9.0) * 0.08;
		float limb = sqrt(max(0.0, 1.0 - r * r));
		vec3 surface = vec3(1.0, 0.97, 0.9) * (0.75 + 0.25 * limb) * (1.0 - maria) * 1.6;
		c = mix(c, surface, smoothstep(1.0, 0.96, r));
	}
	COLOR = c;
}
