shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette_strength = 0.35;
uniform float grain_amount = 0.02;
uniform float saturation = 1.05;
uniform float contrast = 1.03;
uniform float warmth = 0.0;
uniform float exposure = 1.0;
uniform float time_s = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	c *= exposure;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c.r += warmth * 0.06;
	c.b -= warmth * 0.05;
	vec2 uv = SCREEN_UV * 2.0 - 1.0;
	float vig = 1.0 - dot(uv * vec2(0.80, 0.70), uv * vec2(0.80, 0.70)) * vignette_strength;
	c *= clamp(vig, 0.0, 1.0);
	float g = hash12(SCREEN_UV * 1024.0 + fract(time_s) * 137.0) - 0.5;
	c += g * grain_amount;
	COLOR = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
}
