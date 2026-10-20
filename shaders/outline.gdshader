shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

global uniform vec4 g_outline_color : source_color;

uniform float outline_width = 0.045;
// 远海淡出：与 toon.gdshader 的 fade_alpha 同步，抖动剔除轮廓壳
uniform float fade_alpha = 1.0;

float screen_dither(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	if (fade_alpha < 0.999) {
		if (screen_dither(FRAGCOORD.xy) > fade_alpha) {
			discard;
		}
	}
	ALBEDO = g_outline_color.rgb;
}
