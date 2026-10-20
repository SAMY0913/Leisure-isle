shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 灯塔假体积光束。锥壳网格由 main.gd 的 _make_cone_mesh() 在 _build 时生成一次：
// 顶点在灯室中心，沿 -Z 展开；UV.y 0=灯室端 1=该层远端，UV.x 绕轴 0..1。
// _update 只改 uniform / rotation / visibility，不重建任何资源。
uniform vec4 beam_color : source_color = vec4(1.0, 0.84, 0.52, 1.0);
uniform vec4 beam_hot_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform float beam_strength = 1.0;
uniform float beam_softness = 0.55;
uniform float beam_time = 0.0;
uniform float beam_len = 60.0;
uniform float beam_fade_power = 1.8;
uniform float beam_side_power = 2.4;
uniform float beam_noise_amount = 0.08;
uniform float beam_hot_amount = 0.8;
uniform float beam_alpha_max = 0.9;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	float t = clamp(v_uv.y, 0.0, 1.0);
	// 纵向：灯室端快速起亮 → 沿长度指数衰减 → 锥尖归零（消除横贯天空的等宽色带）
	float head = smoothstep(0.0, 0.045, t);
	float tail = pow(clamp(1.0 - t, 0.0, 1.0), beam_fade_power);
	float fade = head * tail;
	// 横向：只取朝向相机的那一面壳（clamp，不用 abs）。正对相机处 ndv≈1 最亮，
	// 掠射轮廓处趋 0 —— 这等价于视线穿过锥体的弦长，中心亮、两侧自然消散；
	// 背面壳完全不发光，避免同一条光束被前后两壁叠加成宽扁色带或硬边。
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float side = pow(ndv, beam_side_power);
	// 缓慢流动的雾纹（只在 fragment 里做数学，不生成资源）
	float scroll = beam_time * (20.0 / max(beam_len, 1.0));
	float n1 = sin(v_uv.x * 21.0 + scroll * 1.7 + t * 4.0);
	float n2 = sin(v_uv.x * 8.0 - scroll * 1.1 - t * 13.0);
	float wisps = 1.0 - beam_noise_amount * (0.5 + 0.5 * n1 * n2);
	// 近灯室白热 → 沿长度过渡到暖金色
	float hot = clamp(beam_hot_amount * pow(clamp(1.0 - t, 0.0, 1.0), 6.0), 0.0, 1.0);
	vec3 col = mix(beam_color.rgb, beam_hot_color.rgb, hot);
	float a = fade * side * wisps * beam_softness * beam_strength;
	ALBEDO = col * (1.0 + hot * 1.1);
	ALPHA = clamp(a, 0.0, beam_alpha_max);
}
