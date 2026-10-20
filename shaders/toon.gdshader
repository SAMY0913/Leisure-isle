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
// 远海淡出：<1 时按屏幕抖动剔除像素（船体/帆/索具统一淡出，不产生透明排序问题）
uniform float fade_alpha = 1.0;

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
		v.x += sin(ph) * 0.055 * h * wind;
		v.z += cos(ph * 0.83 + 1.7) * 0.04 * h * wind;
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
	ALBEDO = col;
}
