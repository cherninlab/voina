shader_type canvas_item;

// Screen-space shading themes (ui/shading.gd) over the finished 3D frame, after the fisheye and
// below the HUD. One pass: pixelate -> flatten (Kuwahara) -> grade (exposure, contrast,
// saturation) -> posterize -> palette -> blood -> ink outlines. Blood is found in the source
// frame by its crimson hue: red well above blue, and blue above green. Lit skin and the raiders'
// shorts are red too but lean orange (green >= blue), so they stay out of the mask. Blood can
// then stay vibrant red even when the rest of the picture is grey, green or a four-colour palette.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float strength = 1.0; // 0 = untouched frame
uniform float pixel = 1.0; // block size in screen pixels
uniform int flat_radius = 0; // Kuwahara radius in blocks; 0 = off
uniform float exposure = 0.0; // stops
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float levels = 0.0; // posterize steps per channel; below 2 = off
uniform int palette_mode = 0; // 0 = luminance ramp, 1 = nearest colour
uniform int palette_count = 0; // 0 = no palette
uniform vec3 palette[8];
uniform float palette_mix = 1.0;
uniform float dither = 0.0; // ordered 4x4 Bayer dither before quantising
uniform float ink = 0.0; // outline opacity
uniform float ink_threshold = 0.25;
uniform vec3 ink_color = vec3(0.0);
uniform float blood_keep = 1.0; // how much detected blood overrides the theme
uniform float blood_threshold = 1.5; // red / blue at which a pixel counts as blood
uniform float blood_hue = 1.12; // blue / green at which a pixel counts as blood (crimson, not orange)
uniform float blood_shade = 0.0; // 0 = flat blood colour, 1 = keeps the source's light and dark
uniform vec3 blood_color = vec3(1.0, 0.0, 0.0);

const int MAX_RADIUS = 4;
const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 fetch(vec2 uv) {
	return textureLod(screen_tex, uv, 0.0).rgb;
}

// Four overlapping quadrants around the pixel; the one with the least colour variance wins.
// Gradients collapse into flat patches while edges stay sharp.
vec3 kuwahara(vec2 uv, vec2 step_uv, int radius) {
	vec3 best = fetch(uv);
	float best_variance = 1e9;
	for (int q = 0; q < 4; q++) {
		vec2 dir = vec2(q % 2 == 0 ? -1.0 : 1.0, q < 2 ? -1.0 : 1.0);
		vec3 sum = vec3(0.0);
		vec3 sum_sq = vec3(0.0);
		float n = 0.0;
		for (int y = 0; y <= MAX_RADIUS; y++) {
			if (y > radius) {
				break;
			}
			for (int x = 0; x <= MAX_RADIUS; x++) {
				if (x > radius) {
					break;
				}
				vec3 c = fetch(uv + vec2(float(x), float(y)) * dir * step_uv);
				sum += c;
				sum_sq += c * c;
				n += 1.0;
			}
		}
		vec3 mean = sum / n;
		vec3 spread = sum_sq / n - mean * mean;
		float variance = spread.r + spread.g + spread.b;
		if (variance < best_variance) {
			best_variance = variance;
			best = mean;
		}
	}
	return best;
}

float blood_mask(vec3 c) {
	float red = smoothstep(blood_threshold, blood_threshold * 1.2, c.r / max(c.b, 0.004));
	float crimson = smoothstep(blood_hue - 0.06, blood_hue + 0.04, c.b / max(c.g, 0.004));
	return red * crimson * smoothstep(0.04, 0.08, c.r);
}

vec3 map_palette(vec3 c, float offset) {
	if (palette_mode == 0) {
		float count = float(palette_count);
		float t = clamp(luma(c) + offset / count, 0.0, 0.9999);
		return palette[clamp(int(floor(t * count)), 0, palette_count - 1)];
	}
	vec3 probe = c + offset * 0.35;
	vec3 best = palette[0];
	float best_distance = 1e9;
	for (int i = 0; i < 8; i++) {
		if (i >= palette_count) {
			break;
		}
		vec3 d = (probe - palette[i]) * vec3(0.3, 0.59, 0.11);
		float dist = dot(d, d);
		if (dist < best_distance) {
			best_distance = dist;
			best = palette[i];
		}
	}
	return best;
}

void fragment() {
	vec2 block = max(pixel, 1.0) * SCREEN_PIXEL_SIZE;
	vec2 cell = floor(SCREEN_UV / block);
	vec2 uv = (cell + 0.5) * block;
	vec3 source = fetch(uv);
	vec3 original = fetch(SCREEN_UV);
	vec3 c = flat_radius > 0 ? kuwahara(uv, block, flat_radius) : source;

	c = c * exp2(exposure);
	c = (c - 0.5) * contrast + 0.5;
	c = mix(vec3(luma(c)), c, saturation);
	c = clamp(c, 0.0, 1.0);

	ivec2 bayer_cell = ivec2(mod(cell, 4.0));
	float offset = (BAYER[bayer_cell.y * 4 + bayer_cell.x] + 0.5) / 16.0 - 0.5;
	if (levels >= 2.0) {
		float steps = levels - 1.0;
		c = clamp(floor(c * steps + 0.5 + offset * dither) / steps, 0.0, 1.0);
	}
	if (palette_count > 0) {
		c = mix(c, map_palette(c, offset * dither), palette_mix);
	}

	// Blood: the source pixel's redness, painted with the theme's blood colour.
	float blood = blood_mask(source) * blood_keep;
	float brightness = clamp(source.r * 2.5, 0.0, 1.0);
	vec3 gore = blood_color * mix(1.0, 0.35 + 0.9 * brightness, blood_shade);
	c = mix(c, gore, blood);

	if (ink > 0.0) {
		// Sobel on the block grid's luminance.
		float tl = luma(fetch(uv + vec2(-1.0, -1.0) * block));
		float tc = luma(fetch(uv + vec2(0.0, -1.0) * block));
		float tr = luma(fetch(uv + vec2(1.0, -1.0) * block));
		float ml = luma(fetch(uv + vec2(-1.0, 0.0) * block));
		float mr = luma(fetch(uv + vec2(1.0, 0.0) * block));
		float bl = luma(fetch(uv + vec2(-1.0, 1.0) * block));
		float bc = luma(fetch(uv + vec2(0.0, 1.0) * block));
		float br = luma(fetch(uv + vec2(1.0, 1.0) * block));
		float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
		float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
		float edge = smoothstep(ink_threshold, ink_threshold * 1.6, length(vec2(gx, gy)));
		c = mix(c, ink_color, edge * ink);
	}

	COLOR = vec4(mix(original, c, strength), 1.0);
}
