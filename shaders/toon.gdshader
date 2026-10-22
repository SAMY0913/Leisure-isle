shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// ---- global lighting state (written every frame by main.gd) ----
global uniform vec4 g_sun_color : source_color;
global uniform vec3 g_sun_dir_view;
global uniform vec4 g_moon_color : source_color;
global uniform vec3 g_moon_dir_view;
global uniform vec4 g_ambient_sky : source_color;
global uniform vec4 g_ambient_ground : source_color;
global uniform vec4 g_fog_color : source_color;
global uniform float g_fog_near;
global uniform float g_fog_far;
global uniform float g_wind_time;
// P8 阶段 6：天气共享参数
global uniform vec4 g_weather;    // x rain, y snow, z wetness, w snow_cover
global uniform vec4 g_weather2;   // x cloud, y storm, z wind, w indoor
global uniform vec4 g_wind_dir;   // x/z 风向，z 风力 0..1
global uniform float g_lightning; // 闪电瞬时亮度 0..1（雷暴/台风；与天空同一来源）
global uniform float g_light_count;
global uniform vec4 g_l0_pos; // xyz world position, w range
global uniform vec4 g_l0_col; // rgb color, w intensity
global uniform vec4 g_l1_pos;
global uniform vec4 g_l1_col;
global uniform vec4 g_l2_pos;
global uniform vec4 g_l2_col;
global uniform vec4 g_l3_pos;
global uniform vec4 g_l3_col;
global uniform vec4 g_l4_pos;
global uniform vec4 g_l4_col;
global uniform vec4 g_l5_pos;
global uniform vec4 g_l5_col;
global uniform vec4 g_l6_pos;
global uniform vec4 g_l6_col;
global uniform vec4 g_l7_pos;
global uniform vec4 g_l7_col;
global uniform vec4 g_l8_pos;
global uniform vec4 g_l8_col;
global uniform vec4 g_l9_pos;
global uniform vec4 g_l9_col;
global uniform vec4 g_l10_pos;
global uniform vec4 g_l10_col;
global uniform vec4 g_l11_pos;
global uniform vec4 g_l11_col;
// lighthouse beam: origin (world), tilted direction, params.x strength / y cos_outer / z cos_inner / w range
global uniform vec3 g_beam_origin;
global uniform vec3 g_beam_dir;
global uniform vec4 g_beam_color;
global uniform vec4 g_beam_params;
// 船载探照灯（聚光）：origin world / dir / rgb+strength / (cos_outer, cos_inner, range, edge)
global uniform vec3 g_spot_origin;
global uniform vec3 g_spot_dir;
global uniform vec4 g_spot_color;
global uniform vec4 g_spot_params;
// Phase6：灯塔光束遮挡盒（世界空间 center/half/yaw，main.gd 一次性写入；解决光穿墙）
global uniform float g_occ_count;
global uniform vec3 g_occ_c0;
global uniform vec3 g_occ_h0;
global uniform float g_occ_y0;
global uniform vec3 g_occ_c1;
global uniform vec3 g_occ_h1;
global uniform float g_occ_y1;
global uniform vec3 g_occ_c2;
global uniform vec3 g_occ_h2;
global uniform float g_occ_y2;
global uniform vec3 g_occ_c3;
global uniform vec3 g_occ_h3;
global uniform float g_occ_y3;
// P8.1-03 冬季白化（季节进度驱动，与 g_weather.w 降雪积雪严格分离）：
// x whiteness 0..1 室外白化度, y frost 霜, z ground_tint 地面泛灰, w foliage_desat 植被去饱和。
// g_winter=0 时本 shader 所有冬季项为 0 → 与 P8 外观逐像素一致（可回滚/A-B）。
global uniform vec4 g_winter;
// 小屋室内体积（世界空间，main.gd 一次性写入；与摄像机无关）：
// g_house = (origin.x, origin.y, origin.z, cos_yaw)
// g_house2 = (sin_yaw, half_x=内墙面, half_z=内墙面, floor_local_y)
// g_roof = (ridge_y, tan_pitch, under_margin, first_floor_top_local_y)（均为房屋局部 y）
global uniform vec4 g_house;
global uniform vec4 g_house2;
global uniform vec4 g_roof;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_tex = 0.0;
uniform vec2 uv_scale = vec2(1.0);
uniform float tex_strength = 1.0;
uniform float detail_bump = 0.0;
uniform float use_vertex_color = 0.0;
uniform float band_count = 4.0;
uniform float band_soft = 0.55;
uniform float rim_amount = 0.15;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.9, 1.0);
uniform float wind = 0.0;
uniform float wind_phase = 0.0;
uniform float glow = 0.0;
uniform float self_lit = 0.0;
uniform float light_wrap = 0.42;
uniform float ambient_amount = 1.0;
// 季节染色（P8）：树冠/灌木等顶点色植被统一乘色；默认白色=不改任何网格。
// 由 main.gd 在季节变化时写入被复制出来的那几份材质，避免污染 isle_math 的共享材质缓存。
uniform vec3 foliage_tint = vec3(1.0);
// 远海淡出：<1 时按屏幕抖动剔除像素（船体/帆/索具统一淡出，不产生透明排序问题）
uniform float fade_alpha = 1.0;
// P8.1-03 材质类别冬季接收系数（main.gd 按对象身份/材质类别写入；默认全接受）：
// x 积雪, y 霜, z 地面泛灰, w 植被去饱和。自发光灯罩/玻璃/海面/船/岛民/花等写入 0。
uniform vec4 winter_recv = vec4(1.0, 1.0, 0.0, 0.0);

varying vec3 v_world;
varying vec2 v_uv;
varying vec3 v_lcol;

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float detail_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = ign(i);
	float b = ign(i + vec2(1.0, 0.0));
	float c = ign(i + vec2(0.0, 1.0));
	float d = ign(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	vec3 v = VERTEX;
	if (wind > 0.0) {
		float h = max(v.y, 0.0);
		float ph = g_wind_time * 1.7 + wind_phase + (MODEL_MATRIX[3].x + MODEL_MATRIX[3].z) * 0.45;
		// 风力同时放大摆幅并给一个顺风向的偏置：小风仍是原来的轻晃，大风/台风才明显歪向一侧。
		float wamp = 0.55 + clamp(g_wind_dir.z, 0.0, 1.0) * 1.15;
		float gust = 0.85 + 0.25 * sin(g_wind_time * 0.73 + wind_phase * 2.1);
		float ox = sin(ph) * 0.055 + sin(ph * 2.7 + 1.3) * 0.016;
		float oz = cos(ph * 0.83 + 1.7) * 0.040 + cos(ph * 3.1) * 0.012;
		float push = clamp(g_wind_dir.z, 0.0, 1.0) * 0.055 * h * wind * gust;
		v.x += (ox * h * wamp + g_wind_dir.x * push) * wind;
		v.z += (oz * h * wamp + g_wind_dir.y * push) * wind;
	}
	VERTEX = v;
	v_world = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	v_uv = UV;
	v_lcol = COLOR.rgb;
}

vec3 add_point_light(vec3 base, vec3 Nw, vec4 lp, vec4 lc) {
	vec3 d = lp.xyz - v_world;
	float dist = length(d);
	vec3 L = d / max(dist, 0.0001);
	float att = clamp(1.0 - dist / max(lp.w, 0.001), 0.0, 1.0);
	att *= att;
	float ndl = dot(Nw, L) * 0.5 + 0.5;
	ndl = pow(clamp(ndl, 0.0, 1.0), 1.5);
	// a soft halo so nearby surfaces read lit even at grazing angles
	return base * lc.rgb * lc.a * att * (0.22 + 0.78 * ndl);
}

float screen_dither(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

// 世界空间射线-AABB（绕 Y 旋转盒）。返回是否命中以及射线停留在盒内的长度。
// 判据：射线在盒内持续 > 0.25m 视为被实体墙遮挡；紧贴表面的受光面 tmax 接近 0，不会被误判。
float beam_occlusion(vec3 p, vec3 n) {
	int cnt = int(g_occ_count);
	if (cnt <= 0) { return 1.0; }
	vec3 ro = p + n * 0.06;
	vec3 rd = normalize(g_beam_origin - ro);
	float occl = 1.0;
	for (int i = 0; i < 4; i++) {
		if (i >= cnt) { break; }
		vec3 c = i == 0 ? g_occ_c0 : (i == 1 ? g_occ_c1 : (i == 2 ? g_occ_c2 : g_occ_c3));
		vec3 h = i == 0 ? g_occ_h0 : (i == 1 ? g_occ_h1 : (i == 2 ? g_occ_h2 : g_occ_h3));
		float yaw = i == 0 ? g_occ_y0 : (i == 1 ? g_occ_y1 : (i == 2 ? g_occ_y2 : g_occ_y3));
		if (h.x < 0.001 || h.y < 0.001 || h.z < 0.001) { continue; }
		float cs = cos(-yaw);
		float sn = sin(-yaw);
		vec3 lp = ro - c;
		vec3 p2 = vec3(cs * lp.x - sn * lp.z, lp.y, sn * lp.x + cs * lp.z);
		vec3 d2 = vec3(cs * rd.x - sn * rd.z, rd.y, sn * rd.x + cs * rd.z);
		vec3 inv = 1.0 / d2;
		vec3 t0 = (-h - p2) * inv;
		vec3 t1 = ( h - p2) * inv;
		vec3 tmin3 = min(t0, t1);
		vec3 tmax3 = max(t0, t1);
		float tnear = max(max(tmin3.x, tmin3.y), tmin3.z);
		float tfar = min(min(tmax3.x, tmax3.y), tmax3.z);
		if (tfar >= tnear && tfar > 0.0) {
			float stay = tfar - max(tnear, 0.0);
			// 盒内穿行越久越接近完全遮挡；0.2m 起生效，1.2m 以上视为完全挡住
			occl = min(occl, 1.0 - smoothstep(0.20, 1.20, stay) * 0.94);
		}
	}
	return occl;
}

// P8.1-03 室内体积掩码（0=室外/外壳, 1=一层室内或阁楼室内）。
// 完全由物体的世界坐标与房屋几何决定，与摄像机位置无关：窗外看室内、走进室内、
// 从阁楼洞口俯视一层都得到同一结果。房屋局部坐标：root 原点在室内地坪下方，
// 一层地坪 y=0.55，内墙面 |x|=3.5 / |z|=2.8，屋脊 y=6.20，屋面斜率 tan=2.47/3.8。
float indoor_mask(vec3 wp) {
	vec3 d = wp - g_house.xyz;
	float c = g_house.w;
	float s = g_house2.x;
	float lx = c * d.x - s * d.z;
	float lz = s * d.x + c * d.z;
	if (abs(lx) > g_house2.y || abs(lz) > g_house2.z) {
		return 0.0;
	}
	if (d.y < g_house2.w) {
		return 0.0;
	}
	// 一层室内（含天花板底面与阁楼楼板，均为室内构件）
	if (d.y <= g_roof.w) {
		return 1.0;
	}
	// 阁楼室内：屋面底板以下（外坡屋面/瓦片在阈值之上，判为室外）
	float roof_under = g_roof.x - g_roof.y * abs(lx) - g_roof.z;
	if (d.y <= roof_under) {
		return 1.0;
	}
	return 0.0;
}

void fragment() {
	if (fade_alpha < 0.999) {
		if (screen_dither(FRAGCOORD.xy) > fade_alpha) {
			discard;
		}
	}
	vec3 N = normalize(NORMAL);
	vec3 Nw = normalize((INV_VIEW_MATRIX * vec4(N, 0.0)).xyz);
	if (detail_bump > 0.0) {
		float e = 0.06;
		float n1 = detail_noise(v_uv * uv_scale * 1.7);
		float n2 = detail_noise(v_uv * uv_scale * 1.7 + vec2(13.1, 7.7));
		float n3 = detail_noise(v_uv * uv_scale * 1.7 + vec2(3.3, 21.7));
		Nw = normalize(Nw + vec3(n1 - n2, 0.0, n2 - n3) * detail_bump * e * 6.0);
	}
	vec3 base = albedo.rgb;
	if (use_tex > 0.5) {
		vec3 t = texture(albedo_tex, v_uv * uv_scale).rgb;
		base = mix(base, base * t * 2.0, clamp(tex_strength, 0.0, 1.0));
	}
	if (use_vertex_color > 0.5) {
		base *= v_lcol;
	}
	base *= foliage_tint;
	// 雨后的湿润：整体压暗一点，再在受光后加一层低强度湿面反光（不引入透明/排序问题）
	float wet = clamp(g_weather.z, 0.0, 1.0);
	base *= 1.0 - 0.26 * wet;
	// ---- P8.1-03 冬季白化：室内体积掩码（摄像机无关）+ 材质类别接收系数 ----
	// 顺序：wet -> frost/desaturate/ground_tint -> snow（见下面积雪块）。
	// g_winter=0 时所有项为 0，外观与 P8 完全一致。
	float indoor = indoor_mask(v_world);
	float lit_exempt = 1.0 - step(0.5, self_lit);   // 自发光灯罩/炉火不吃白化
	float winter_vis = g_winter.x * (1.0 - indoor) * lit_exempt;
	float w_snow = clamp(winter_vis * winter_recv.x, 0.0, 1.0);
	float w_frost = clamp(g_winter.y * (1.0 - indoor) * lit_exempt * winter_recv.y, 0.0, 1.0);
	float w_ground = clamp(g_winter.z * (1.0 - indoor) * lit_exempt * winter_recv.z, 0.0, 1.0);
	float w_desat = clamp(g_winter.w * (1.0 - indoor) * lit_exempt * winter_recv.w, 0.0, 1.0);
	if (w_desat > 0.001) {
		float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
		base = mix(base, vec3(luma), w_desat * 0.55);
	}
	if (w_ground > 0.001) {
		base = mix(base, mix(base, vec3(0.62, 0.64, 0.60), 0.50), w_ground * 0.70);
	}
	if (w_frost > 0.001) {
		float upw = clamp(Nw.y * 0.5 + 0.5, 0.0, 1.0);
		base = mix(base, base * 0.55 + vec3(0.72, 0.78, 0.87) * 0.45, w_frost * (0.28 + 0.72 * upw));
	}
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 col;
	if (self_lit > 0.5) {
		col = base * glow;
	} else {
		float ndl = dot(N, normalize(g_sun_dir_view));
		float q = clamp(ndl, 0.0, 1.0) * band_count;
		float fr = fract(q);
		float soft = clamp(band_soft, 0.001, 0.999);
		float cel = (floor(q) + smoothstep(0.5 - soft * 0.5, 0.5 + soft * 0.5, fr)) / band_count;
		float ndl_m = max(dot(N, normalize(g_moon_dir_view)), 0.0);
		float mooncel = smoothstep(0.35, 0.45, ndl_m) * 0.30;
		vec3 ambient = mix(g_ambient_ground.rgb, g_ambient_sky.rgb, clamp(Nw.y * 0.5 + 0.5, 0.0, 1.0)) * 0.56 * ambient_amount;
		vec3 warm = g_sun_color.rgb * 0.62;
		col = base * (ambient + g_sun_color.rgb * cel * 0.62 + g_moon_color.rgb * mooncel);
		float fres = pow(1.0 - clamp(dot(Nw, V), 0.0, 1.0), 3.2);
		col += g_sun_color.rgb * rim_color.rgb * fres * rim_amount;
		col += base * glow;
		// local lamps / windows / fireplace: analytic point lights in world space
		// lighthouse rotating beam: cheap analytic spot (unshaded pipeline)
		if (g_beam_params.x > 0.001) {
			vec3 bto = v_world - g_beam_origin;
			float bdist = length(bto);
			vec3 bdir = bto / max(bdist, 0.0001);
			float bcone = smoothstep(g_beam_params.y, g_beam_params.z, dot(bdir, normalize(g_beam_dir)));
			float batt = clamp(1.0 - bdist / max(g_beam_params.w, 0.001), 0.0, 1.0);
			batt *= batt;
			vec3 bl = normalize(g_beam_origin - v_world);
			float bndl = clamp(dot(Nw, bl) * 0.5 + 0.5, 0.0, 1.0);
			// P5.2：灯塔扫过时岛屿/屋顶/船体要有可辨的受光变化。旧系数 0.18~1.0 在夜间
			// 深色 toon 基色上几乎看不出；提高漫反射系数并加一点与基色无关的暖色散射，
			// 让深色植被/岩石表面也能被光束扫亮。
			float blit = g_beam_params.x * bcone * batt;
			// Phase6：实体墙遮挡——从受光点向灯室发射线，穿过小屋实体盒则不接受直射光。
			blit *= beam_occlusion(v_world, Nw);
			col += base * g_beam_color.rgb * blit * (0.22 + 0.78 * bndl) * 1.9;
			col += g_beam_color.rgb * blit * 0.05;
		}
		// 船载探照灯：真实影响船头前方的海面 / 岛岸 / 其他物体
		if (g_spot_color.a > 0.001) {
			vec3 sto = v_world - g_spot_origin;
			float sdist = length(sto);
			vec3 sdir = sto / max(sdist, 0.0001);
			float scone = smoothstep(g_spot_params.x, g_spot_params.y, dot(sdir, normalize(g_spot_dir)));
			float satt = clamp(1.0 - sdist / max(g_spot_params.z, 0.001), 0.0, 1.0);
			satt *= satt;
			float sndl = clamp(dot(Nw, normalize(g_spot_origin - v_world)) * 0.5 + 0.5, 0.0, 1.0);
			col += base * g_spot_color.rgb * g_spot_color.a * scone * satt * (0.14 + 0.86 * sndl);
		}
		// 湿面反光：视线越掠射越亮，白天最明显，夜里几乎看不见
		float wet_sheen = pow(1.0 - clamp(dot(Nw, V), 0.0, 1.0), 3.5) * wet * 0.16;
		col += g_sun_color.rgb * wet_sheen;
		// 积雪：只挂“朝上的面”，用世界坐标噪声打散边界；厚度 g_weather.w 越大，越斜的面也开始挂雪。
		// 低处（沙滩/岸边）按世界高度淡出，避免整座岛像被白漆刷过一遍。
		float snow_amt = clamp(g_weather.w, 0.0, 1.0);
		float snow_cov = smoothstep(0.02, 0.42, snow_amt);
		float up_mask = smoothstep(0.0, 1.0 - clamp(snow_amt, 0.0, 0.95) * 0.88, clamp(Nw.y, 0.0, 1.0));
		float nz = detail_noise(v_world.xz * 0.42 + v_world.y * 0.7);
		float patchy = 0.62 + 0.38 * nz;
		patchy *= 0.82 + 0.18 * detail_noise(v_world.xz * 1.7 + v_world.y * 1.3);
		// U11：这是海平面岸线淡出（海平面 y=0，岛面 y≈7.4-7.9 恒为 1），不是“岛面无雪”的判据；
		// 岛面高程依据 isle_math.gd:77-110 profile_at。P8 降雪行为保持不变。
		float snow_line = smoothstep(1.05, 3.20, v_world.y);
		// 降雪积雪（g_weather.w）与季节白化（g_winter.x）严格分离，取 max 合成；室内不吃任何雪。
		float snow_weather = clamp(up_mask * snow_cov * patchy * snow_line, 0.0, 1.0) * (1.0 - indoor);
		float snow_winter = clamp(smoothstep(0.05, 0.72, clamp(Nw.y, 0.0, 1.0)) * w_snow
			* patchy * smoothstep(0.50, 2.20, v_world.y), 0.0, 1.0);
		float snow_m = max(snow_weather, snow_winter);
		if (snow_m > 0.001) {
			vec3 snow_col = vec3(0.90, 0.93, 0.99) * clamp(
				ambient * 1.85 + g_sun_color.rgb * (0.26 + 0.52 * cel) + g_moon_color.rgb * 0.80, 0.0, 1.6);
			col = mix(col, snow_col, snow_m * 0.84);
		}
		int lc_n = int(g_light_count);
		if (lc_n > 0) {
			col += add_point_light(base, Nw, g_l0_pos, g_l0_col);
			if (lc_n > 1) { col += add_point_light(base, Nw, g_l1_pos, g_l1_col); }
			if (lc_n > 2) { col += add_point_light(base, Nw, g_l2_pos, g_l2_col); }
			if (lc_n > 3) { col += add_point_light(base, Nw, g_l3_pos, g_l3_col); }
			if (lc_n > 4) { col += add_point_light(base, Nw, g_l4_pos, g_l4_col); }
			if (lc_n > 5) { col += add_point_light(base, Nw, g_l5_pos, g_l5_col); }
			if (lc_n > 6) { col += add_point_light(base, Nw, g_l6_pos, g_l6_col); }
			if (lc_n > 7) { col += add_point_light(base, Nw, g_l7_pos, g_l7_col); }
			if (lc_n > 8) { col += add_point_light(base, Nw, g_l8_pos, g_l8_col); }
			if (lc_n > 9) { col += add_point_light(base, Nw, g_l9_pos, g_l9_col); }
			if (lc_n > 10) { col += add_point_light(base, Nw, g_l10_pos, g_l10_col); }
			if (lc_n > 11) { col += add_point_light(base, Nw, g_l11_pos, g_l11_col); }
		}
	}
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float fogf = smoothstep(g_fog_near, g_fog_far, dist);
	col = mix(col, g_fog_color.rgb, fogf);
	// 闪电：按受光面反照率提亮（保持颜色，不给整屏刷白），朝上的面更亮；
	// 远处被雾/霾罩住的物体不应和近景一样亮，否则远岛会像"浮空白块"。
	col += (base * 0.44 + vec3(0.020, 0.024, 0.032)) * g_lightning
		* (0.55 + 0.45 * clamp(Nw.y, 0.0, 1.0)) * (1.0 - fogf * 0.85);
	ALBEDO = col;
}
