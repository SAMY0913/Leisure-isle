shader_type spatial;
// 真实玻璃（unshaded 自定义管线）：
//  - 菲涅尔天空反射 + 太阳反射光斑 / 镜面高光（正面 4% ~ 掠射全反射）
//  - 轻微屏幕空间折射：按视空间法线偏移 SCREEN_UV，位移 <= 0.01，权重低
//  - 吸收色（tint/opacity）与发光（夜间窗光，main 每帧写 glow）
//  - 薄盒/圆筒等封闭网格：cull_back 只画朝相机的一面，避免双面叠加成乳白蓝板
//  - depth_draw_never：玻璃不写深度，不遮挡室内家具，交给不透明物体与排序
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

global uniform vec4 g_sun_color : source_color;
global uniform vec3 g_sun_dir_view;
global uniform vec4 g_ambient_sky : source_color;
global uniform vec4 g_ambient_ground : source_color;
global uniform vec4 g_fog_color : source_color;
global uniform float g_fog_near;
global uniform float g_fog_far;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform vec4 tint : source_color = vec4(0.62, 0.72, 0.76, 1.0);
// opacity = 法线入射时的吸收不透明度（薄玻璃取 0.05~0.15），不再直接当整体 alpha
uniform float opacity : hint_range(0.0, 1.0) = 0.10;
uniform float glow = 0.0;
uniform vec4 glow_col : source_color = vec4(1.0, 0.72, 0.42, 1.0);
uniform float surface_rough = 0.06;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.34;
uniform float fresnel_f0 : hint_range(0.0, 0.25) = 0.045;
uniform float fresnel_power : hint_range(1.0, 8.0) = 5.0;
uniform float reflection_gain : hint_range(0.0, 4.0) = 1.65;
uniform float sun_spec_gain : hint_range(0.0, 4.0) = 0.85;
uniform float sun_shininess : hint_range(8.0, 512.0) = 220.0;
uniform float refract_strength : hint_range(0.0, 0.01) = 0.006;
uniform float refract_weight : hint_range(0.0, 1.0) = 0.55;
// 正视角度的基础微反射（真实玻璃表面在法线入射也有 >4% 反射 + 污渍散射），
// 让正视时玻璃仍有"存在感"，不会变成一个空洞。
uniform float front_sheen : hint_range(0.0, 0.15) = 0.030;
// 远海淡出（与 toon.gdshader 同名同义）：main.gd 只给声明了 fade_alpha 的材质做淡出副本，
// 船窗也复用本材质，因此这里必须暴露 fade_alpha，用屏幕抖动剔除实现远处渐隐。
uniform float fade_alpha = 1.0;
// 夜间窗光增益：main.gd 每帧写 glow（0.05~0.6），用来模拟室内灯把玻璃照亮。
uniform float glow_gain : hint_range(0.0, 6.0) = 2.8;

varying vec3 v_world;

float screen_dither(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 与 toon.gdshader:113-114 完全一致的抖动剔除，供船窗远海淡出使用
	if (fade_alpha < 0.999) {
		if (screen_dither(FRAGCOORD.xy) > fade_alpha) {
			discard;
		}
	}
	vec3 N = normalize(NORMAL);
	// 世界法线（toon 相同约定：INV_VIEW_MATRIX 把视空间法线转世界）
	vec3 Nw = normalize((INV_VIEW_MATRIX * vec4(N, 0.0)).xyz);
	vec3 Vw = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 Sw = normalize((INV_VIEW_MATRIX * vec4(normalize(g_sun_dir_view), 0.0)).xyz);
	float ndv = clamp(dot(Nw, Vw), 0.0, 1.0);
	// Schlick 菲涅尔：正面 ~f0，掠射趋近 1
	float fres = fresnel_f0 + (1.0 - fresnel_f0) * pow(clamp(1.0 - ndv, 0.0, 1.0), fresnel_power);
	fres = clamp(fres, 0.0, 1.0);

	// ---- 天空反射（按反射向量的世界高度取天空/地面环境色）----
	vec3 Rw = reflect(-Vw, Nw);
	float up = clamp(Rw.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 refl = mix(g_ambient_ground.rgb, g_ambient_sky.rgb, smoothstep(0.30, 0.82, up)) * reflection_gain;
	// 地平线附近的雾光带，让反射不只是纯色块
	float horizon = pow(1.0 - clamp(abs(Rw.y), 0.0, 1.0), 6.0);
	refl += g_fog_color.rgb * horizon * 0.30;
	// 反射中的太阳光斑：宽光晕 + 亮核
	float sd = clamp(dot(Rw, Sw), 0.0, 1.0);
	refl += g_sun_color.rgb * (pow(sd, 10.0) * 0.16 + pow(sd, 380.0) * 1.35);

	// ---- 屏幕空间折射：视空间法线 xy 偏移，长度钳制 <= 0.01 ----
	vec2 off = vec2(N.x, -N.y) * refract_strength * (0.35 + 0.65 * (1.0 - ndv));
	float off_len = length(off);
	if (off_len > 0.01) {
		off *= 0.01 / off_len;
	}
	vec3 bg_flat = texture(screen_tex, SCREEN_UV).rgb;
	vec3 bg_refr = texture(screen_tex, clamp(SCREEN_UV + off, vec2(0.001), vec2(0.999))).rgb;
	// 只取"偏移带来的颜色差"作为折射修正，主透射仍由 alpha 混合的帧缓冲给出；
	// 限制幅度、低权重，避免轮廓鬼影，也不额外遮挡室内（不画不透明玻璃面）。
	vec3 bg_delta = clamp(bg_refr - bg_flat, vec3(-0.12), vec3(0.12)) * refract_weight;

	// ---- 吸收：opacity 作为法线入射吸收率 ----
	// 最终 = alpha*ALBEDO + (1-alpha)*背景 = f_s*refl + (1-f_s)*(1-absorb)*背景。
	// 吸收只衰减透射光，不额外加"吸收色"自发光——否则夜间玻璃会变成灰白奶玻璃。
	float absorb = clamp(opacity, 0.0, 0.92);
	float f_s = clamp(fres + front_sheen * (1.0 - fres), 0.0, 1.0);
	float alpha = clamp(f_s + absorb * (1.0 - f_s), 0.02, 0.97);
	vec3 refl_tint = mix(vec3(1.0), tint.rgb, tint_strength);
	vec3 col = (f_s * refl * refl_tint) / max(alpha, 0.02);
	// 经过 alpha 混合后折射增量会变成 (1-alpha)*bg_delta，故此处除以 alpha 抵消，
	// 使最终像素 = f_s*refl + (1-alpha)*bg + (1-alpha)*bg_delta：真实的小幅屏幕空间折射。
	col += bg_delta * (1.0 - alpha) / max(alpha, 0.10);

	// ---- 太阳镜面高光（玻璃表面，HDR，配合 main 的 glow 后处理）----
	vec3 Hw = normalize(Sw + Vw);
	float nh = clamp(dot(Nw, Hw), 0.0, 1.0);
	float spec = pow(nh, sun_shininess);
	col += g_sun_color.rgb * spec * sun_spec_gain / max(alpha, 0.10);
	// 宽一点的柔光
	col += g_sun_color.rgb * pow(nh, sun_shininess * 0.06) * 0.035 * sun_spec_gain / max(alpha, 0.10);

	// ---- 夜间窗光（main 每帧写 glow；由 alpha 混合自然衰减）----
	col += glow_col.rgb * glow * glow_gain;

	// 远处玻璃的反射随雾衰减（透射部分已包含雾后的背景，不再二次加雾）
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float fogf = smoothstep(g_fog_near, g_fog_far, dist);
	col = mix(col, g_fog_color.rgb, fogf * 0.25);

	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = surface_rough;
}
