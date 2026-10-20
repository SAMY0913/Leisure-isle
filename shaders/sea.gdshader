shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
// ============================================================================
// P6 海面（T3 视觉）：7 组方向波 + 画质档细节（波数/法线/泡沫/反射增强）
//
// 关键契约：wave_h()/wave_grad() 的 7 组系数必须与 scripts/isle_waves.gd 的 WAVES 表
// 逐项一致（同 amp/kx/kz/omega/phase/need）。tools/probe_water6.gd 会解析本文件文本
// 逐系数比对，并用 CPU 端复算 200 个采样点。船体吃水/俯仰 = main._wave_h() ->
// IsleWaves.height()，与本文件同源；改这里必须同步改 isle_waves.gd。
// ============================================================================

// ---- 外部由 main.gd 驱动的调色/光向 ----
uniform vec4 water_deep : source_color = vec4(0.02, 0.08, 0.14, 1.0);
uniform vec4 water_mid : source_color = vec4(0.03, 0.14, 0.22, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.05, 0.23, 0.32, 1.0);
uniform vec4 water_foam : source_color = vec4(0.88, 0.93, 0.95, 1.0);
uniform vec4 spec : source_color = vec4(0.93, 1.0, 1.0, 1.0);
uniform vec4 glitter : source_color = vec4(0.95, 1.0, 1.0, 1.0);
uniform vec4 sky_zenith : source_color = vec4(0.10, 0.30, 0.60, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.40, 0.60, 0.80, 1.0);
uniform vec4 sky_haze : source_color = vec4(0.50, 0.65, 0.80, 1.0);
uniform vec4 cloud_light : source_color = vec4(0.78, 0.82, 0.90, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.30, 0.36, 0.48, 1.0);
uniform vec4 fog_color : source_color = vec4(0.30, 0.40, 0.55, 1.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_i = 1.0;
uniform float moon_i = 0.0;
uniform float glitter_i = 1.0;
uniform float moon_phase = 1.0;
uniform float fog_near = 100.0;
uniform float fog_far = 600.0;
uniform float time_s = 0.0;
uniform float cloud_opacity = 0.5;

// ---- 内部手感参数（main._apply_quality 覆盖，均有安全默认值） ----
uniform float wave_height = 1.0;   // 大尺度起伏（main 传 0.5，与 CPU IsleWaves 同源）
uniform float wave_detail = 2.0;   // 位移波数档 0..3（0->3, 1->4, 2->6, 3->7 组）
uniform float foam_amount = 0.86;  // 白沫总量
uniform float island_refl = 1.0;   // 岛屿/岸线在近岸水面的倒影强度
uniform float sea_normal_detail = 1.0;   // 细碎法线强度（画质档）
uniform float sea_foam_detail = 1.7;     // 泡沫分层数（画质档：>0.5 二层, >1.5 三层卷浪）
uniform float sea_refl_detail = 1.0;     // 反射细节档（画质档：加云絮/树线/夜间灯影）
uniform float ssr_strength = 0.0;         // P6 反射细节增强强度（0=关闭；main 写 IsleQuality 的 sea_ssr 值 .58/.62）
uniform float wave_scale = 1.0;          // 表面细节尺度（main 预留参数，1=默认）
// 旧 SSR 接口保留（main._update_lighting 每帧 set_shader_parameter("ssr_cam_vp", ...)，
// 为避免 main 侧报错保留声明；当前解析版 reflect_extra 不使用它）。
uniform mat4 ssr_cam_vp = mat4(0.0);
// 说明（实测教训，见 docs/P6_RESEARCH_VISUAL.md）：这里曾用 hint_screen_texture 做「屏幕空间反射」，
// 但 sea 是不透明 pass，采样屏幕纹理拿到的是未合成天空/后续不透明的中间画面，窗口实测会让 q3/q4
// 整屏发白并出现竖条纹伪影（ssr 0.58 时 mean lum .495->.529、sat .687->.553）。因此已改为纯解析的
// 反射细节增强 reflect_extra()：更细的云絮 + 日/月方向的暖冷反光带，不依赖屏幕纹理。
// sea_screen_tex 的 hint_screen_texture 已移除（上面 ssr_cam_vp 仅为兼容 main 的写入而保留声明）。
// ---- 灯塔旋转光束（global uniforms，由 main.gd 每帧写入） ----
global uniform vec3 g_beam_origin;
global uniform vec3 g_beam_dir;
global uniform vec4 g_beam_color;
global uniform vec4 g_beam_params; // x strength, y cos_outer, z cos_inner, w range
// 船载探照灯（聚光）：与 toon.gdshader 同一组 global uniform
global uniform vec3 g_spot_origin;
global uniform vec3 g_spot_dir;
global uniform vec4 g_spot_color;
global uniform vec4 g_spot_params;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm3(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(9.3, 5.7);
		a *= 0.5;
	}
	return s;
}

// ---------- 多尺度定向波（7 组，波长 140 / 78 / 41 / 24 / 16 / 34.7 / 20 m） ----------
// 前 5 组 = P5 原系数（观感连续），后 2 组为 P6 新增交叉涌浪（detail>=1.5 / >=2.5 启用）。
// gate(need) 与 isle_waves.gd 的 WAVES[].need 一一对应（probe_water6 逐行解析本函数）。
float gate(float need) {
	return step(need - 0.0001, wave_detail);
}

float wave_h(vec2 p, float t) {
	float h = 0.0;
	h += 0.420 * gate(0.0) * sin(dot(p, vec2(0.035, 0.028)) + t * 0.420 + 0.000);
	h += 0.260 * gate(0.0) * sin(dot(p, vec2(-0.061, 0.052)) + t * 0.580 + 1.700);
	h += 0.150 * gate(0.0) * sin(dot(p, vec2(0.124, -0.087)) + t * 0.860 + 3.100);
	h += 0.085 * gate(0.5) * sin(dot(p, vec2(-0.201, -0.168)) + t * 1.220 + 5.000);
	h += 0.050 * gate(1.5) * sin(dot(p, vec2(0.317, 0.244)) + t * 1.630 + 0.600);
	h += 0.072 * gate(1.5) * sin(dot(p, vec2(0.148, 0.212)) + t * 1.020 + 2.350);
	h += 0.038 * gate(2.5) * sin(dot(p, vec2(-0.256, 0.183)) + t * 1.380 + 4.450);
	return h * wave_height;
}

vec2 wave_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	float c;
	c = gate(0.0) * cos(dot(p, vec2(0.035, 0.028)) + t * 0.420 + 0.000);
	g += 0.420 * vec2(0.035, 0.028) * c;
	c = gate(0.0) * cos(dot(p, vec2(-0.061, 0.052)) + t * 0.580 + 1.700);
	g += 0.260 * vec2(-0.061, 0.052) * c;
	c = gate(0.0) * cos(dot(p, vec2(0.124, -0.087)) + t * 0.860 + 3.100);
	g += 0.150 * vec2(0.124, -0.087) * c;
	c = gate(0.5) * cos(dot(p, vec2(-0.201, -0.168)) + t * 1.220 + 5.000);
	g += 0.085 * vec2(-0.201, -0.168) * c;
	c = gate(1.5) * cos(dot(p, vec2(0.317, 0.244)) + t * 1.630 + 0.600);
	g += 0.050 * vec2(0.317, 0.244) * c;
	c = gate(1.5) * cos(dot(p, vec2(0.148, 0.212)) + t * 1.020 + 2.350);
	g += 0.072 * vec2(0.148, 0.212) * c;
	c = gate(2.5) * cos(dot(p, vec2(-0.256, 0.183)) + t * 1.380 + 4.450);
	g += 0.038 * vec2(-0.256, 0.183) * c;
	return g * wave_height;
}

// ---------- 与岛屿地形完全一致的岸线 / 海床深度 ----------
float coast_radius(float a) {
	return 25.5 + 2.8 * sin(3.0 * a + 0.70) + 1.9 * cos(5.0 * a - 1.20)
		+ 1.1 * sin(7.0 * a + 2.10) + 0.7 * cos(11.0 * a + 0.40);
}

float seabed_depth(vec2 p) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float n = r / max(0.001, coast_radius(a));
	float d = 0.0;
	d += 3.1 * smoothstep(1.00, 1.14, n);
	d += 2.5 * smoothstep(1.14, 1.30, n);
	d += 1.8 * smoothstep(1.30, 1.60, n);
	return d;
}

// 细碎法线扰动（画质档 sea_normal_detail 控制强度）：两层滚动噪声的有限差分坡度。
vec2 detail_grad(vec2 p, float t) {
	float d = clamp(sea_normal_detail, 0.0, 2.2);
	if (d < 0.01) {
		return vec2(0.0);
	}
	float e = 0.28;
	vec2 p1 = p * 0.42 + vec2(t * 0.11, -t * 0.075);
	vec2 p2 = p * 1.15 + vec2(-t * 0.19, t * 0.145);
	float n1 = vnoise(p1);
	float n2 = vnoise(p2);
	vec2 g1 = vec2(vnoise(p1 + vec2(e, 0.0)) - n1, vnoise(p1 + vec2(0.0, e)) - n1) / e;
	vec2 g2 = vec2(vnoise(p2 + vec2(e, 0.0)) - n2, vnoise(p2 + vec2(0.0, e)) - n2) / e;
	return (g1 * 0.42 + g2 * 1.15) * d * 0.085;
}

// ---------- 天空/云/日月在反射方向上的解析采样（不在水面重复整帧渲染） ----------
vec3 sky_reflect(vec3 R) {
	float y = clamp(R.y, 0.0, 1.0);
	vec3 c = mix(sky_horizon.rgb, sky_zenith.rgb, pow(y, 0.55));
	c = mix(c, sky_haze.rgb, exp(-y * 9.0) * 0.45);

	vec3 sd = normalize(sun_dir);
	float cs = max(dot(R, sd), 0.0);
	float sun_up = smoothstep(-0.03, 0.03, sd.y);
	c += spec.rgb * (pow(cs, 10.0) * 0.20 + pow(cs, 260.0) * 1.60) * clamp(sun_i, 0.0, 2.5) * sun_up * 0.55;

	vec3 md = normalize(moon_dir);
	float cm = max(dot(R, md), 0.0);
	float moon_up = smoothstep(-0.03, 0.04, md.y);
	c += vec3(0.86, 0.92, 1.0) * (pow(cm, 24.0) * 0.10 + pow(cm, 500.0) * 1.1)
		* clamp(moon_i, 0.0, 1.5) * clamp(moon_phase, 0.05, 1.0) * moon_up * 0.45;

	if (cloud_opacity > 0.03 && y > 0.015) {
		vec2 cp = R.xz / (y + 0.16) * 0.52;
		vec2 drift = vec2(time_s * 0.0042, time_s * 0.0017);
		float n = fbm3(cp + drift) * 0.66 + fbm3(cp * 2.2 - drift * 1.5 + 5.0) * 0.34;
		if (sea_refl_detail >= 1.5) {
			// 反射细节档：加一层更细的云絮，倒影里能看出卷云结构
			n = n * 0.74 + fbm3(cp * 4.4 + drift * 0.6 + 11.0) * 0.26;
		}
		float mask = smoothstep(0.46, 0.72, n) * cloud_opacity * smoothstep(0.015, 0.12, y);
		float lit = smoothstep(0.44, 0.82, n);
		float dayf = clamp(sun_i, 0.0, 1.6);
		vec3 cc = mix(cloud_shade.rgb, cloud_light.rgb, lit) * (0.30 + 0.70 * min(dayf, 1.0));
		cc += spec.rgb * pow(cs, 6.0) * 0.22;
		if (sea_refl_detail >= 2.0) {
			// 极致档：云背光银边（太阳在云后时的透光），倒影更接近天空 shader
			cc += spec.rgb * pow(cs, 3.0) * 0.12 * (1.0 - lit) * sun_up;
		}
		c = mix(c, cc, clamp(mask, 0.0, 1.0) * (0.22 + 0.58 * min(dayf, 1.0)));
	}
	return c;
}

// 近岸水面对岛屿的倒影近似：反射射线朝向岛心时，按近岸距离混入草/岩/木的暗色
vec3 land_reflect(vec3 R, vec2 wp, float r, float coast) {
	vec2 to_center = -wp / max(0.001, length(wp));
	vec2 rh = R.xz;
	float rhl = length(rh);
	if (rhl < 0.0001) return vec3(0.0);
	rh /= rhl;
	float toward = max(dot(rh, to_center), 0.0);
	float near_shore = smoothstep(40.0, 1.0, r - coast);
	float w = toward * toward * near_shore * island_refl;
	if (w < 0.002) return vec3(0.0);

	float n = vnoise(wp * 0.33) * 0.55 + vnoise(wp * 0.91 + 7.0) * 0.30 + vnoise(wp * 2.3 - 3.0) * 0.15;
	vec3 grass = vec3(0.115, 0.155, 0.075);
	vec3 rock = vec3(0.175, 0.165, 0.140);
	vec3 wood = vec3(0.270, 0.175, 0.095);
	vec3 land = mix(grass, rock, smoothstep(0.52, 0.88, n));
	land = mix(land, wood, smoothstep(0.80, 0.97, n) * 0.65);
	if (sea_refl_detail >= 1.5) {
		// 树线剪影：岸上植被在水里的暗色竖影，比均匀绿更有"岛"的轮廓感
		float tree = vnoise(wp * vec2(0.17, 0.11) + 3.1) * 0.55 + vnoise(wp * vec2(0.53, 0.34) - 1.7) * 0.45;
		land = mix(land, vec3(0.070, 0.100, 0.058), smoothstep(0.40, 0.80, tree) * 0.42);
	}
	if (sea_refl_detail >= 2.0) {
		// 岸上暖灯在水面拉长的竖直倒影（夜间才出现，用太阳高度角当夜色代理）
		float night = clamp(1.0 - sun_i * 2.2, 0.0, 1.0);
		float lamp0 = smoothstep(0.72, 0.95, vnoise(wp * vec2(0.85, 0.075) + vec2(0.0, time_s * 0.35)));
		land += vec3(1.00, 0.58, 0.24) * lamp0 * night * 0.30;
	}
	float sun_up = clamp(normalize(sun_dir).y * 2.6 + 0.10, 0.0, 1.0);
	land *= (0.30 + 0.85 * sun_up * clamp(sun_i, 0.0, 2.0));
	land += vec3(0.05, 0.06, 0.08) * clamp(moon_i, 0.0, 1.5) * 0.35;
	return land * w;
}

// P6 反射细节增强（极高/极致档）：纯解析，不使用屏幕纹理。
// 内容：比 sky_reflect 更细的高空云絮 + 太阳方向的暖色反光带（低太阳时偏橙）+ 月光冷色反光。
// 权重小且 clamp，只作为「更贵的反射」锦上添花，不会造成整屏提亮。
vec3 reflect_extra(vec3 R) {
	vec3 c = vec3(0.0);
	float ry = R.y;
	if (ry > 0.005) {
		vec2 cp = R.xz / (ry + 0.14) * 0.92;
		float n1 = fbm3(cp * 2.6 + vec2(time_s * 0.0042, time_s * 0.0016));
		float n2 = fbm3(cp * 5.1 - vec2(time_s * 0.0027, 0.0) + vec2(4.7, 11.3));
		float m = smoothstep(0.54, 0.80, n1 * 0.72 + n2 * 0.28);
		m *= smoothstep(0.01, 0.12, ry) * clamp(cloud_opacity, 0.0, 1.0);
		c += mix(cloud_shade.rgb, cloud_light.rgb, 0.62) * m * 0.55;
		vec3 sd = normalize(sun_dir);
		float cs = max(dot(R, sd), 0.0);
		float low = 1.0 - smoothstep(0.05, 0.42, sd.y);
		vec3 sun_tint = mix(spec.rgb, vec3(1.0, 0.74, 0.46), 0.55 * low);
		c += sun_tint * (pow(cs, 160.0) * 0.55 + pow(cs, 24.0) * 0.10) * clamp(sun_i, 0.0, 2.5);
		vec3 md = normalize(moon_dir);
		float cm = max(dot(R, md), 0.0);
		c += vec3(0.62, 0.74, 1.0) * pow(cm, 90.0) * 0.35 * clamp(moon_i, 0.0, 2.0);
	}
	return c;
}

varying vec2 v_wp;

void vertex() {
	vec2 wp = VERTEX.xz;
	VERTEX.y += wave_h(wp, time_s);
	v_wp = wp;
}

void fragment() {
	vec2 wp = v_wp;
	float t = time_s;
	float depth = seabed_depth(wp);
	float r = length(wp);
	float a = atan(wp.y, wp.x);
	float coast = coast_radius(a);

	// 法线：大尺度波 + 细节噪声，叠加后归一
	vec2 grad = wave_grad(wp, t) * 0.55 + detail_grad(wp, t);
	vec2 jitter = vec2(
		vnoise(wp * 0.33 + vec2(t * 0.05, 0.0)) - 0.5,
		vnoise(wp * 0.33 + vec2(17.3, -t * 0.05)) - 0.5
	) * 0.05;
	vec3 N = normalize(vec3(-(grad.x + jitter.x), 1.0, -(grad.y + jitter.y)));
	vec3 wpos = vec3(wp.x, wave_h(wp, t), wp.y);
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	float ndv = clamp(dot(N, V), 0.0, 1.0);

	// 水体颜色：按海床深度分层，波峰处更透亮（次表面感）
	float h = wave_h(wp, t);
	float crest = smoothstep(0.20, 0.95, h) * 0.5 + 0.5;
	vec3 body = mix(water_shallow.rgb, water_mid.rgb, smoothstep(0.15, 2.6, depth));
	body = mix(body, water_deep.rgb, smoothstep(2.6, 9.0, depth));
	body *= 0.94 + 0.12 * crest;
	body += water_shallow.rgb * 0.10 * crest * clamp(sun_i, 0.0, 2.0);

	// Fresnel + 天空/云/日月反射
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 R = reflect(-V, N);
	vec3 refl = sky_reflect(R);
	vec3 col = mix(body, refl, clamp(fres, 0.0, 0.88));

	// 近岸岛屿倒影
	col += land_reflect(R, wp, r, coast);

	// P6 反射细节增强（极高/极致档）：解析细云絮 + 日/月方向反光带（不用屏幕纹理，避免洗白）
	if (ssr_strength > 0.001) {
		vec3 extra = reflect_extra(R);
		float extra_w = clamp(ssr_strength * (0.55 + 0.45 * fres), 0.0, 0.75);
		col += extra * extra_w;
	}

	// 太阳高光：主瓣（锐）+ 宽光带（柔）+ 动态碎光，避免固定亮条
	vec3 sd = normalize(sun_dir);
	float sun_up = smoothstep(-0.045, 0.02, sd.y);
	vec3 H = normalize(V + sd);
	float ndh = max(dot(N, H), 0.0);
	float sun_hi = pow(ndh, 420.0) * 3.0 + pow(ndh, 56.0) * 0.11;
	col += spec.rgb * sun_hi * clamp(sun_i, 0.0, 2.5) * 0.62 * sun_up;

	float spark = vnoise(wp * 2.35 + vec2(t * 0.85, -t * 1.15));
	float spark2 = vnoise(wp * 5.4 - vec2(t * 1.3, t * 0.7));
	float glint = smoothstep(0.70, 0.97, spark * 0.6 + spark2 * 0.4);
	glint *= pow(ndh, 46.0);
	col += glitter.rgb * glint * glitter_i * 0.85 * sun_up;

	// 月光高光与月光碎光
	vec3 md = normalize(moon_dir);
	float moon_up = smoothstep(-0.045, 0.03, md.y);
	vec3 Hm = normalize(V + md);
	float ndhm = max(dot(N, Hm), 0.0);
	float moon_hi = pow(ndhm, 380.0) * 1.2 + pow(ndhm, 40.0) * 0.045;
	col += spec.rgb * moon_hi * clamp(moon_i, 0.0, 1.6) * clamp(moon_phase, 0.08, 1.0) * 0.55 * moon_up;
	float mglint = smoothstep(0.74, 0.98, spark2) * pow(ndhm, 60.0);
	col += vec3(0.80, 0.88, 1.0) * mglint * clamp(moon_i, 0.0, 1.5) * 0.42 * moon_up;

	// 灯塔光束扫过海面：按真实三维光锥与起伏水面求交（与 toon 材质的锥体判定完全一致）。
	// 光束有俯角，水面上的亮区是椭圆足迹；随旋转横扫海面。
	if (g_beam_params.x > 0.001) {
		vec3 bd = normalize(g_beam_dir);
		vec3 fp = vec3(wp.x, h, wp.y);
		vec3 bto = fp - g_beam_origin;
		float bdist = length(bto);
		float bcone = smoothstep(g_beam_params.y, g_beam_params.z, dot(bto / max(bdist, 0.0001), bd));
		float batt = clamp(1.0 - bdist / max(g_beam_params.w, 0.001), 0.0, 1.0);
		batt *= batt;
		float sweep = bcone * batt * g_beam_params.x;
		float bglint = smoothstep(0.55, 0.95, spark * 0.7 + spark2 * 0.3);
		col += (water_shallow.rgb * 0.85 + vec3(0.16, 0.18, 0.14)) * sweep * (0.54 + bglint * 0.85);
		col += g_beam_color.rgb * sweep * (0.20 + 0.55 * bglint);
	}
	// 船载前向探照灯：照亮船头前的海面（可见柔光锥在 boat_spot.gdshader，实际受光在这里）
	if (g_spot_color.a > 0.001) {
		vec3 fp2 = vec3(wp.x, h, wp.y);
		vec3 sto = fp2 - g_spot_origin;
		float sdist = length(sto);
		float scone = smoothstep(g_spot_params.x, g_spot_params.y, dot(sto / max(sdist, 0.0001), normalize(g_spot_dir)));
		float satt = clamp(1.0 - sdist / max(g_spot_params.z, 0.001), 0.0, 1.0);
		satt *= satt;
		float sglint = smoothstep(0.52, 0.94, spark2 * 0.6 + spark * 0.4);
		col += (water_shallow.rgb * 0.55 + g_spot_color.rgb * 0.35) * g_spot_color.a * scone * satt * (0.85 + sglint * 0.9);
	}
	// 白沫：近岸冲刷带 + 破碎浪线 + 波峰白帽，两层噪声各司其职
	float fn = fbm3(wp * 0.40 + vec2(t * 0.06, -t * 0.02));
	float fn2 = fbm3(wp * 1.35 - vec2(t * 0.10, t * 0.05) + 9.0);
	float shore = 1.0 - smoothstep(0.0, 2.6, depth);
	float band = sin(depth * 6.2 - t * 1.55 + fn * 4.2) * 0.5 + 0.5;
	float foam_shore = smoothstep(0.44, 0.82, band * 0.34 + shore * 0.66) * (1.0 - smoothstep(1.0, 3.0, depth));
	foam_shore += smoothstep(0.68, 0.95, fn) * shore * 0.24;
	foam_shore += smoothstep(0.82, 0.97, fn2) * exp(-max(depth - 0.4, 0.0) * 1.6) * 0.30;
	float foam_crest = smoothstep(0.54, 0.90, (h / max(0.15, wave_height)) + (fn2 - 0.5) * 0.35);
	float foam = clamp(foam_shore + foam_crest * 0.24, 0.0, 1.0) * foam_amount;
	if (sea_foam_detail > 0.5) {
		// 泡沫二层：把边缘打散成絮状，避免一条硬边
		float fn3 = fbm3(wp * 3.10 - vec2(t * 0.16, t * 0.08) + 21.0);
		foam *= 0.88 + 0.26 * smoothstep(0.28, 0.82, fn3);
		foam = clamp(foam + smoothstep(0.80, 0.985, fn3) * shore * 0.16 * foam_amount, 0.0, 1.0);
	}
	if (sea_foam_detail > 1.5) {
		// 泡沫三层：卷破浪花（只在高浪峰、稀疏）
		float fn4 = fbm3(wp * 2.35 + vec2(t * 0.21, -t * 0.13) + 3.7);
		float spray = smoothstep(0.86, 0.995, fn4);
		float crest_f = smoothstep(0.62, 0.95, h / max(0.15, wave_height));
		foam = clamp(foam + spray * crest_f * 0.30 * foam_amount, 0.0, 1.0);
	}
	// 泡沫颜色随日光/月光明暗变化，夜间不再是一条死白亮边
	float foam_light = clamp(0.32 + clamp(sun_i, 0.0, 1.5) * 0.42 + clamp(moon_i, 0.0, 1.2) * 0.10, 0.10, 1.0);
	col = mix(col, water_foam.rgb * foam_light, clamp(foam, 0.0, 1.0) * 0.60);
	col *= 1.0 + 0.06 * clamp(sun_i, 0.0, 2.0) * (1.0 - foam);

	// 远处雾气 + 8bit 抖动
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float fogf = smoothstep(fog_near, fog_far, dist);
	col = mix(col, fog_color.rgb, fogf);
	float dq = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	col += (dq - 0.5) * (1.0 / 255.0);
	ALBEDO = col;
}