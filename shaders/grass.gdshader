shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

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
global uniform vec4 g_l0_pos;
global uniform vec4 g_l0_col;
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
// P8.1-03 冬季白化（与 toon.gdshader 同名同义；由 main.gd 每帧/一次性写入）：
// g_winter = (whiteness, frost, ground_tint, foliage_desat)；g_house/g_house2/g_roof = 小屋室内体积。
global uniform vec4 g_winter;
global uniform vec4 g_house;
global uniform vec4 g_house2;
global uniform vec4 g_roof;

uniform sampler2D blade_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float wind = 0.6;
uniform float transparency = 1.0;
// P8.1-03 材质类别接收系数：(x 积雪, y 霜, z 地面泛灰, w 去饱和)，默认全是接受。
uniform vec4 winter_recv = vec4(1.0, 1.0, 0.0, 0.0);

varying vec3 v_world;
varying vec2 v_uv;
varying vec3 v_lcol;
varying float v_h;

void vertex() {
	vec3 v = VERTEX;
	float h = clamp(v.y, 0.0, 1.0);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = g_wind_time * 1.9 + origin.x * 0.37 + origin.z * 0.29;
	float sway = sin(ph) * 0.55 + sin(ph * 2.3 + 1.7) * 0.18;
	// 天气风力：小风保持原来的轻晃，大风/台风时摆幅明显加大并整体偏向风向。
	float wg = 0.55 + clamp(g_wind_dir.z, 0.0, 1.0) * 1.25;
	float gust = 0.88 + 0.22 * sin(g_wind_time * 0.61 + origin.z * 0.5);
	v.x += (sway * h * h * 0.42 * wg + g_wind_dir.x * clamp(g_wind_dir.z, 0.0, 1.0) * h * h * 0.30) * wind * gust;
	v.z += (cos(ph * 0.81) * h * h * 0.26 * wg + g_wind_dir.y * clamp(g_wind_dir.z, 0.0, 1.0) * h * h * 0.30) * wind * gust;
	v.y *= 1.0;
	VERTEX = v;
	v_uv = UV;
	v_h = h;
	v_lcol = COLOR.rgb;
	v_world = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
}

// P8.1-03 室内体积掩码（与 toon.gdshader 完全一致的房屋几何；草叶一般只在室外，
// 但保证外墙/门廊附近与「窗外看室内」口径统一，不依赖摄像机位置）。
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
	if (d.y <= g_roof.w) {
		return 1.0;
	}
	float roof_under = g_roof.x - g_roof.y * abs(lx) - g_roof.z;
	return d.y <= roof_under ? 1.0 : 0.0;
}

void fragment() {
	vec4 tx = texture(blade_tex, v_uv);
	if (tx.a < 0.36) {
		discard;
	}
	vec3 Nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// grass reads mostly up-facing even on crossed cards
	Nw = normalize(mix(Nw, vec3(0.0, 1.0, 0.0), 0.55));
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	float ndl = dot(Nw, normalize(g_sun_dir_view)) * 0.5 + 0.5;
	float cel = smoothstep(0.25, 0.85, ndl);
	vec3 base = tint.rgb * v_lcol * tx.rgb * (0.6 + 0.4 * v_h);
	// 湿润压暗 + 积雪时草叶发白（深雪时 main 会进一步降低草材质透明度，露出一片雪地）
	base *= 1.0 - clamp(g_weather.z, 0.0, 1.0) * 0.22;
	// P8.1-03：竖立的草叶不再整片刷 55% 白，而是按「朝上的叶面」加权；
	// 冬季白化（季节进度）与降雪积雪（g_weather.w）分离后叠加；室内叶面不吃白。
	float indoor = indoor_mask(v_world);
	float w_pres = g_winter.x * (1.0 - indoor);
	float blade_up = smoothstep(0.15, 0.85, clamp(Nw.y, 0.0, 1.0));
	float white_amt = clamp((clamp(g_weather.w, 0.0, 1.0) * 0.55
		+ w_pres * winter_recv.x * 0.90) * (0.20 + 0.80 * blade_up), 0.0, 1.0);
	base = mix(base, vec3(0.90, 0.93, 1.0), white_amt);
	// 冬季去饱和（让残绿退成枯草色）与地面泛灰（winter_recv.z）。
	float w_desat = clamp(g_winter.w * (1.0 - indoor) * winter_recv.w, 0.0, 1.0);
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base = mix(base, luma * vec3(0.94, 0.96, 1.0), w_desat * 0.45);
	float w_ground = clamp(g_winter.z * (1.0 - indoor) * winter_recv.z, 0.0, 1.0);
	base = mix(base, mix(base, vec3(0.60, 0.62, 0.58), 0.50), w_ground * 0.60);
	vec3 ambient = mix(g_ambient_ground.rgb, g_ambient_sky.rgb, 0.72) * 0.62;
	float moon = max(dot(Nw, normalize(g_moon_dir_view)), 0.0);
	vec3 col = base * (ambient + g_sun_color.rgb * cel * 0.78 + g_moon_color.rgb * moon * 0.22);
	// 夜间局部暖光：草叶靠近灯时应受光，否则在灯下是一团黑
	if (g_light_count > 0.5) {
		float lamp = 0.0;
		for (int i = 0; i < 8; i++) {
			if (float(i) >= g_light_count) { break; }
			vec4 lp = g_l0_pos;
			vec4 lc = g_l0_col;
			if (i == 1) { lp = g_l1_pos; lc = g_l1_col; }
			else if (i == 2) { lp = g_l2_pos; lc = g_l2_col; }
			else if (i == 3) { lp = g_l3_pos; lc = g_l3_col; }
			else if (i == 4) { lp = g_l4_pos; lc = g_l4_col; }
			else if (i == 5) { lp = g_l5_pos; lc = g_l5_col; }
			else if (i == 6) { lp = g_l6_pos; lc = g_l6_col; }
			else if (i == 7) { lp = g_l7_pos; lc = g_l7_col; }
			vec3 d = lp.xyz - v_world;
			float dist = length(d);
			float att = clamp(1.0 - dist / max(lp.w, 0.001), 0.0, 1.0);
			att *= att;
			float ndl2 = clamp(dot(Nw, d / max(dist, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
			lamp += att * (0.25 + 0.75 * ndl2) * lc.a;
		}
		col += base * vec3(1.0, 0.78, 0.48) * lamp;
	}
	float fres = pow(1.0 - clamp(dot(Nw, V), 0.0, 1.0), 2.0);
	col += g_sun_color.rgb * fres * 0.10;
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float fogf = smoothstep(g_fog_near, g_fog_far, dist) * 0.8;
	col = mix(col, g_fog_color.rgb, fogf);
	col += (base * 0.36 + vec3(0.016, 0.020, 0.028)) * g_lightning * (1.0 - fogf * 0.85);
	ALBEDO = col;
	ALPHA = tx.a * transparency;
	ALPHA_SCISSOR_THRESHOLD = 0.34;
}
