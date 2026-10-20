shader_type sky;
render_mode use_debanding;

uniform vec4 sky_zenith : source_color = vec4(0.03, 0.07, 0.18, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.09, 0.16, 0.30, 1.0);
uniform vec4 sky_haze : source_color = vec4(0.12, 0.21, 0.38, 1.0);
uniform vec4 sun_glow : source_color = vec4(0.11, 0.17, 0.32, 1.0);
uniform vec4 sun_disk_col : source_color = vec4(0.04, 0.09, 0.19, 1.0);
uniform vec4 moon_disk_col : source_color = vec4(0.87, 0.92, 1.0, 1.0);
uniform vec4 cloud_light : source_color = vec4(0.33, 0.40, 0.61, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.12, 0.16, 0.32, 1.0);

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_disk_i = 0.0;
uniform float moon_disk_i = 0.0;
uniform float star_alpha = 0.0;
uniform float moon_alpha = 1.0;
uniform float cloud_opacity = 0.5;
// 云层档位（与 IsleQuality.sky_cloud_detail 一一对应）：
// 0 = 无云（低档）、1 = 卷云 + 丝云、2 = 再加厚度积云（高/极高）、
// 2.5+ = 第 4 层高空卷云带 + 更密的星空/银河（极致）
uniform float cloud_detail = 2.0;
uniform float moon_phase = 1.0;
uniform float moon_waxing = 1.0;
uniform float time_s = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
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
		p = p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return s;
}

float fbm4(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return s;
}

// 三层云：常驻薄卷云 + 高层被风拉长的絮状云 + 低层成团的体积云。
// 用“朝太阳方向再采样一次密度”的差值近似云体自阴影，形成亮面/暗面/银边。
// cloud_detail 控制成本：0 无云、1 只保留絮云、2 再加一层体积云。
vec4 cloud_layers(vec3 d, float y, float cos_sun, float sun_up) {
	if (cloud_detail < 0.5 || y < 0.012) {
		return vec4(0.0);
	}
	vec2 sun_flat = normalize(sun_dir.xz + vec2(0.0001, 0.0001));
	vec3 out_col = vec3(0.0);
	float out_a = 0.0;

	// --- 常驻薄卷云：不依赖低云强度，保证正午/晴天天空也有可读的云层细节 ---
	{
		vec2 cp = d.xz / (y + 0.30) * 0.24;
		vec2 drift = vec2(time_s * 0.0012, -time_s * 0.0007);
		vec2 warp = vec2(
			fbm3(cp * 2.0 + vec2(1.7, -time_s * 0.0009)),
			fbm3(cp * 2.0 + vec2(6.4, time_s * 0.0008))
		) - 0.5;
		float n = fbm4(cp * 1.35 + warp * 0.9 + drift);
		float n2 = fbm3(cp * 1.35 + warp * 0.9 + drift + sun_flat * 0.06);
		float m = smoothstep(0.40, 0.66, n) * smoothstep(0.002, 0.055, y) * (0.16 + 0.24 * cloud_opacity);
		float lit = clamp(0.52 + (n - n2) * 7.0, 0.0, 1.0);
		vec3 c = mix(cloud_shade.rgb * 0.78, cloud_light.rgb * 1.06, lit);
		c += sun_glow.rgb * pow(max(cos_sun, 0.0), 6.0) * 0.16 * (1.0 - lit);
		out_col = mix(out_col, c, m);
		out_a = max(out_a, m);
	}

	// --- 高层：细长丝云 ---
	if (cloud_detail >= 0.5) {
		vec2 cp = d.xz / (y + 0.24) * 0.40;
		vec2 drift = vec2(time_s * 0.0042, time_s * 0.0016);
		vec2 warp = vec2(
			fbm3(cp * 1.6 + vec2(2.3, -time_s * 0.0015)),
			fbm3(cp * 1.6 + vec2(8.1, time_s * 0.0012))
		) - 0.5;
		float n = fbm4(cp + warp * 0.55 + drift) * 0.72
			+ fbm3(cp * 2.6 - warp * 0.35 + vec2(5.0, 0.0)) * 0.28;
		float n2 = fbm3(cp + warp * 0.55 + drift + sun_flat * 0.10) * 0.72
			+ fbm3(cp * 2.6 + sun_flat * 0.16 + 5.0) * 0.28;
		float m = smoothstep(0.31, 0.55, n) * smoothstep(0.002, 0.030, y) * 0.94;
		float lit = clamp(0.50 + (n - n2) * 5.6, 0.0, 1.0);
		vec3 c = mix(cloud_shade.rgb * 0.80, cloud_light.rgb * 1.06, lit);
		c += sun_glow.rgb * (pow(max(cos_sun, 0.0), 5.0) * 0.40 + 0.04) * (1.0 - lit) * 0.9;
		c += sun_glow.rgb * pow(max(cos_sun, 0.0), 64.0) * 1.1 * sun_up;
		c *= 0.92 + 0.16 * y;
		out_col = mix(out_col, c, m);
		out_a = max(out_a, m);
	}

	// --- 低层：成团体积云（有厚度感，仅高画质） ---
	if (cloud_detail > 1.5) {
		vec2 cp = d.xz / (y + 0.34) * 0.92;
		vec2 drift = vec2(-time_s * 0.0026, time_s * 0.0010);
		vec2 warp = vec2(
			fbm3(cp * 1.9 + vec2(4.0, time_s * 0.001)),
			fbm3(cp * 1.9 + vec2(-2.0, 0.0))
		) - 0.5;
		float n = fbm4(cp + warp * 0.6 + drift) * 0.76
			+ fbm3(cp * 3.0 - warp * 0.4 + vec2(9.0, 1.0)) * 0.24;
		float n2 = fbm3(cp + warp * 0.6 + drift + sun_flat * 0.14) * 0.76
			+ fbm3(cp * 3.0 + sun_flat * 0.2 + 9.0) * 0.24;
		float m = smoothstep(0.41, 0.65, n) * cloud_opacity * smoothstep(0.002, 0.028, y) * 0.96;
		float lit = clamp(0.50 + (n - n2) * 6.0, 0.0, 1.0);
		// 底部偏暗、顶部偏亮，叠一点暖色银边
		float thick = smoothstep(0.55, 0.85, n);
		vec3 c = mix(cloud_shade.rgb * 0.72, cloud_light.rgb * 1.06, lit * (0.45 + 0.55 * thick));
		c = mix(c, cloud_shade.rgb * 1.06, (1.0 - thick) * 0.35);
		c += sun_glow.rgb * pow(max(cos_sun, 0.0), 9.0) * 0.34 * (1.0 - lit);
		c += sun_glow.rgb * pow(max(cos_sun, 0.0), 90.0) * 0.9 * sun_up;
		out_col = mix(out_col, c, m);
		out_a = max(out_a, m);
	}
	// --- 第 4 层：高空卷云带（极致档）：被风拉长的细丝 + 稀薄银边 ---
	if (cloud_detail > 2.5) {
		vec2 cp = d.xz / (y + 0.52) * 0.62;
		cp.x *= 0.42;
		vec2 drift = vec2(time_s * 0.0060, time_s * 0.0018);
		float n = fbm4(cp * vec2(1.0, 2.6) + drift) * 0.66
			+ fbm3(cp * 4.2 - drift * 0.6 + vec2(3.0, 7.0)) * 0.34;
		float n2 = fbm3(cp * vec2(1.0, 2.6) + drift + sun_flat * 0.12) * 0.66
			+ fbm3(cp * 4.2 + sun_flat * 0.18 + vec2(3.0, 7.0)) * 0.34;
		float m = smoothstep(0.54, 0.74, n) * smoothstep(0.004, 0.060, y) * 0.42;
		float lit = clamp(0.55 + (n - n2) * 5.0, 0.0, 1.0);
		vec3 c = mix(cloud_shade.rgb * 0.86, cloud_light.rgb * 1.02, lit);
		c += sun_glow.rgb * pow(max(cos_sun, 0.0), 12.0) * 0.22 * (1.0 - lit);
		c += sun_glow.rgb * pow(max(cos_sun, 0.0), 128.0) * 0.7 * sun_up;
		out_col = mix(out_col, c, m);
		out_a = max(out_a, m);
	}
	return vec4(out_col, clamp(out_a, 0.0, 1.0));
}

// 星空：三层不同尺度/亮度，星点大小与亮度都有变化，缓慢闪烁 + 银河带
vec3 star_field(vec3 d, float y, float detail) {
	if (star_alpha < 0.01 || y < -0.02) {
		return vec3(0.0);
	}
	vec3 acc = vec3(0.0);
	vec3 tint_cool = vec3(0.62, 0.72, 0.95);
	vec3 tint_warm = vec3(0.95, 0.86, 0.72);
	for (int i = 0; i < 4; i++) {
		float sc = 110.0 + float(i) * 85.0;
		vec3 sp = d * sc;
		vec3 cell = floor(sp);
		vec3 f = fract(sp) - 0.5;
		float h = hash13(cell + float(i) * 37.0);
		float h2 = hash13(cell * 1.73 + 11.0);
		float threshold = 0.9855 + float(i) * 0.0018;
		float bright = pow(clamp((h - threshold) / (1.0 - threshold), 0.0, 1.0), 1.8);
		float tw = 0.62 + 0.38 * sin(time_s * (0.7 + h2 * 1.7) + h2 * 91.0);
		float size = mix(0.16, 0.46, h2);
		float star = bright * tw * smoothstep(size, 0.0, length(f));
		vec3 tint = mix(tint_cool, tint_warm, h2);
		acc += tint * star * (1.15 - float(i) * 0.16);
	}
	// 极致档：两层更暗的小星，补齐星空的密度层次（星等分布更真实）
	if (detail > 2.5) {
		for (int j = 0; j < 2; j++) {
			float sc = 560.0 + float(j) * 430.0;
			vec3 sp = d * sc;
			vec3 cell = floor(sp);
			vec3 f = fract(sp) - 0.5;
			float h = hash13(cell + float(j) * 71.0 + 19.0);
			float h2 = hash13(cell * 2.11 + 5.0);
			float threshold = 0.9865 + float(j) * 0.0028;
			float bright = pow(clamp((h - threshold) / (1.0 - threshold), 0.0, 1.0), 1.4);
			float tw = 0.70 + 0.30 * sin(time_s * (0.9 + h2 * 2.1) + h2 * 47.0);
			float star = bright * tw * smoothstep(mix(0.10, 0.26, h2), 0.0, length(f));
			acc += mix(tint_cool, tint_warm, h2) * star * (0.72 - float(j) * 0.10);
		}
	}
	// 银河：沿一个倾斜大圆带状的淡雾（与星空同一个时间来源，不引入新时钟）
	float mw = fbm4(d.xz * 2.1 + d.y * 1.3 + 3.0);
	float band_w = mix(2.4, 3.1, step(2.5, detail));
	float band = exp(-pow((d.y - 0.26) * band_w, 2.0)) * (0.55 + 0.45 * mw);
	acc += vec3(0.52, 0.60, 0.80) * band * mix(0.09, 0.13, step(2.5, detail));
	// 极致档：银河暗尘带，让光带不是一条均匀的雾
	if (detail > 2.5) {
		float dust = fbm3(d.xz * 6.3 + d.y * 4.1 + 17.0);
		acc -= vec3(0.30, 0.34, 0.46) * band * smoothstep(0.42, 0.68, dust) * 0.10;
	}
	return acc * star_alpha * smoothstep(-0.02, 0.14, y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;

	// 天顶 -> 地平线 -> 霾层
	vec3 col = mix(sky_horizon.rgb, sky_zenith.rgb, pow(clamp(y, 0.0, 1.0), 0.52));
	col = mix(col, sky_haze.rgb, exp(-max(y, 0.0) * 11.0) * 0.55);
	float below = 1.0 - smoothstep(-0.22, 0.0, y);
	col = mix(col, sky_haze.rgb * 0.52, below * 0.85);

	vec3 sd = normalize(sun_dir);
	vec3 md = normalize(moon_dir);
	float cos_sun = clamp(dot(d, sd), -1.0, 1.0);
	float sun_up = smoothstep(-0.10, 0.05, sd.y);

	// 太阳光晕 + 低空暖带：暖带强度/色温随太阳高度角连续变化（日出日落不发灰、不硬切）
	float low_sun = 1.0 - smoothstep(0.055, 0.34, sd.y);
	vec3 warm_band = mix(sun_glow.rgb, vec3(1.00, 0.46, 0.18), 0.42 * low_sun);
	float glow = pow(max(cos_sun, 0.0), 8.0) * 0.5 + pow(max(cos_sun, 0.0), 48.0) * 0.9;
	col += sun_glow.rgb * glow * (0.28 + 0.72 * sun_up);
	float az = atan(d.x, -d.z);
	float saz = atan(sd.x, -sd.z);
	float ad = abs(mod(az - saz + 3.14159265, 6.2831853) - 3.14159265);
	col += warm_band * exp(-ad * (2.1 - 0.5 * low_sun)) * exp(-max(y, 0.0) * (6.5 - 2.0 * low_sun)) * (0.42 + 0.30 * low_sun) * sun_up;
	col += sun_glow.rgb * pow(max(cos_sun, 0.0), 2.0) * 0.06 * sun_up;
	// 反日方向的"维纳斯带"/地球阴影：日出日落时贴地平线的淡暖色，强化时间感
	float anti = 3.14159265 - ad;
	col += vec3(0.52, 0.29, 0.30) * exp(-pow(anti * 1.1, 2.0)) * exp(-max(y, 0.0) * 9.0) * 0.11 * low_sun * sun_up;

	float disk = smoothstep(0.99955, 0.99978, cos_sun);
	float disk_vis = clamp(sun_disk_i, 0.0, 3.0) * smoothstep(-0.02, 0.03, sd.y);
	// 日盘色温随高度角连续变化：低空橙红、高空偏白（不硬切，避免日落瞬间跳色）
	vec3 disk_warm = vec3(1.00, 0.46, 0.16);
	vec3 disk_hi = vec3(1.00, 0.96, 0.88);
	vec3 disk_tint = mix(disk_warm, disk_hi, smoothstep(0.015, 0.42, sd.y));
	vec3 sun_c = mix(sun_disk_col.rgb, disk_tint, 0.45) * (1.4 + sun_disk_i * 2.8);
	// 日盘边缘的一圈暖光，让低空太阳不死板
	col += sun_glow.rgb * pow(max(cos_sun, 0.0), 200.0) * 0.35 * disk_vis;
	col = mix(col, sun_c, disk * clamp(disk_vis, 0.0, 1.0));

	// 月亮：相位阴影 + 月盘光晕
	float cos_moon = clamp(dot(d, md), -1.0, 1.0);
	vec3 upv = abs(md.y) > 0.985 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 mx = normalize(cross(upv, md));
	vec3 my = cross(md, mx);
	vec2 mp = vec2(dot(d, mx), dot(d, my)) / 0.013;
	float mr = length(mp);
	float mdisk = 1.0 - smoothstep(0.92, 1.0, mr);
	if (mdisk > 0.001) {
		float py = clamp(mp.y, -1.0, 1.0);
		float illum = clamp(moon_phase, 0.0, 1.0);
		float term = (1.0 - 2.0 * illum) * sqrt(max(1.0 - py * py, 0.0));
		float lit = moon_waxing > 0.0
			? smoothstep(term - 0.015, term + 0.015, mp.x)
			: smoothstep(term - 0.015, term + 0.015, -mp.x);
		// 月面细节：极淡的环形山亮度起伏，避免纯色圆片
		float crater = vnoise(mp * 3.4 + 5.0) * 0.5 + vnoise(mp * 8.0 - 2.0) * 0.5;
		vec3 mooncol = mix(moon_disk_col.rgb * 0.05, moon_disk_col.rgb * (1.15 + 0.20 * crater), lit);
		float vis = clamp(moon_disk_i * moon_alpha, 0.0, 2.0) * smoothstep(-0.04, 0.06, md.y);
		col = mix(col, mooncol, mdisk * clamp(vis, 0.0, 1.0) * (0.35 + 0.65 * lit));
	}
	col += moon_disk_col.rgb * pow(max(cos_moon, 0.0), 240.0) * 0.08 * moon_alpha;
	col += moon_disk_col.rgb * pow(max(cos_moon, 0.0), 10.0) * 0.025 * moon_alpha * smoothstep(-0.03, 0.06, md.y);

	// 星空（在云之前，云的 alpha 会自然盖住可见部分）
	col += star_field(d, y, cloud_detail);

	// 云层（cloud_detail 0..3）
	vec4 cl = cloud_layers(d, y, cos_sun, sun_up);
	col = mix(col, cl.rgb, cl.a);

	// 8bit 输出抖动
	float dq = fract(sin(dot(EYEDIR.xy * 812.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (dq - 0.5) * (1.0 / 255.0);
	COLOR = col;
}