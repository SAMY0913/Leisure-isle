shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// P8 阶段 6：地面雨滴溅落水花（单个 MultiMesh，横放的小圆环，由 TIME + 每实例相位做循环）。
// 只在地面锚点播动画，不做逐滴模拟：岛上雨点位置固定散布，相机远近都不增加 CPU 成本。

uniform vec4 albedo_color : source_color = vec4(0.90, 0.95, 1.0, 0.66);
uniform float rate = 2.0;        // 每秒循环次数
uniform float strength = 0.0;    // main 按雨强写入；0 = 完全不可见
varying float v_alpha;

void vertex() {
	float phase = INSTANCE_CUSTOM.r;
	float t = fract(TIME * rate + phase);
	float s = 0.14 + t * 0.62;
	VERTEX.xz *= s;
	VERTEX.y += (1.0 - t) * 0.015;
	v_alpha = (1.0 - t) * (1.0 - t) * strength;
}

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float ring = smoothstep(0.52, 0.94, r) * (1.0 - smoothstep(0.94, 1.0, r));
	ALBEDO = albedo_color.rgb;
	ALPHA = ring * v_alpha * albedo_color.a;
}
