// The hooded cultist's garments (T-110): the imported linen, seam, lining and rope looks, with the
// skirt shaped round the legs and the hands kept out of the cloth (robe_shape.gdshaderinc).
shader_type spatial;
render_mode cull_disabled;

#include "res://content/mobs/hooded_cultist/robe_shape.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform float roughness = 0.9;

void vertex() {
	VERTEX = robe_shape(VERTEX);
}

void fragment() {
	vec4 color = albedo;
	if (use_texture) {
		color *= texture(albedo_texture, UV);
	}
	ALBEDO = color.rgb;
	ROUGHNESS = roughness;
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
