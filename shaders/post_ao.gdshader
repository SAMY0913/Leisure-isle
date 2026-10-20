shader_type spatial;
// P6 自定义屏幕空间 AO（Ambient Occlusion）——透明 pass 乘法叠层版（T3）。
//
// 为什么不用 Environment.ssao：本项目 toon / sea / sky / glass 全部是自定义 unshaded 着色器，
// Godot 内置 SSAO 只写入 forward 光照的间接光项，对 unshaded 输出没有可见影响（已实测无差异）。
//
// 实现方式（关键教训，实测）：
//   早期版本是「不透明 pass 里读 hint_screen_texture 再把场景色乘 (1-ao) 写回去」，
//   但 Godot 4 Forward+ 的不透明 pass 里 screen_texture 不是最终画面（天空/后续不透明物尚未合成），
//   整屏会被一层错误颜色的蒙版覆盖 —— 表现为 q2/q3/q4 全屏发白（已窗口实测复现）。
//   现在改为「透明 pass 的纯乘法叠层」：
//     ALBEDO = vec3(0.0); ALPHA = ao;   →  屏幕结果 = dst * (1 - ao)
//   不需要 screen_tex，也不会覆盖任何像素（alpha=0 处完全透传）；深度纹理在透明 pass 同样可用。
//
// P6 重影修复（task-8，2026-10-20，窗口实测根因）：
//   旧版 AO 在「高」及以上档（q2 ao=0.35 / q3 0.55 / q4 0.75）会出现阁楼窗「鬼影」：
//   半球采样把像素前方视距远得多（例：室内 15m 深处 vs 窗棂 6.4m）的前景几何当成遮挡 ——
//   深度差无上限；而 1m 世界半径在 6m 视距处的屏幕投影偏移可达窗宽的 10%+，
//   于是每个室内像素都多出被前景窗棂/梁架压出的「暗色副本」，看起来就是重影/黑色糊块。
//   修复三点：
//     ① 每个采样点的遮挡深度差限制在 rr * 1.8 内并做淡出 —— 前景 9m 的窗棂不再遮挡室内；
//     ② 四邻深度必须有效且视距跳变 < 阈值才重建法线，轮廓（含天空邻域）像素直接不施加 AO，
//        消除屋顶/窗框轮廓外的黑色糊块；
//     ③ AO 强度映射改为 pow(occ * 1.35, ao_contrast) * ao_strength（旧版 *3.2、 *2.4 会饱和到全黑）。
//   实测窗洞区亮度比：q2 0.496 -> 修复后应 >0.92；q4 0.369 -> 修复后应 >0.88（见 probe_ghost6）。
//
// 挂载（main.gd 侧）：
//   var mi := MeshInstance3D.new()
//   mi.mesh = QuadMesh.new()            # 默认 1x1，在 XY 平面
//   mi.material_override = ao_mat       # ShaderMaterial，shader = preload("res://shaders/post_ao.gdshader")
//   ao_mat.render_priority = 127        # 最后叠
//   mi.extra_cull_margin = 16384.0
//   mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
//   mi.position = Vector3(0, 0, -0.6)   # 相机前方即可，顶点着色器会把 POSITION 铺满全屏
//   camera.add_child(mi)
// 参数：ao_strength = 画质档的 ao_strength（低/中档 0 时节点隐藏；高 0.35、极高 0.55、极致 0.75），
//       ao_radius = 0.9，ao_samples = 12~16，ao_bias = 0.025，ao_contrast = 1.4，ao_max_dist = 90。
//
// 注意：顶点着色器覆盖 POSITION 为全屏 NDC；depth_test_disabled + depth_draw_never，
// 不写深度、不参与遮挡。天空像素（反向 Z 深度=0）与 ao_max_dist 以外直接 alpha=0 透传。

render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform float ao_strength : hint_range(0.0, 1.0) = 0.55;
uniform float ao_radius : hint_range(0.05, 4.0) = 0.9;
uniform int ao_samples : hint_range(4, 24) = 12;
uniform float ao_bias : hint_range(0.0, 0.5) = 0.025;
uniform float ao_max_dist : hint_range(1.0, 400.0) = 90.0;
uniform float ao_contrast : hint_range(0.5, 4.0) = 1.4;
uniform int depth_convention : hint_range(0, 1) = 0;
uniform int ao_debug : hint_range(0, 4) = 0;

// 片段阶段没有 PROJECTION_MATRIX（Godot 4 spatial 限制），从顶点传过来。
varying mat4 v_proj;

// 注意（Godot 4.7 实测限制）：用户函数体内不能引用 stage built-ins（如 INV_PROJECTION_MATRIX /
// CAMERA_POSITION_WORLD），否则报 Unknown identifier。因此矩阵由调用处作为参数传入。
vec3 view_pos_z(mat4 inv_proj, vec2 uv, float z_ndc) {
	vec4 vp = inv_proj * vec4(uv * 2.0 - 1.0, z_ndc, 1.0);
	return vp.xyz / max(vp.w, 1e-6);
}

// 深度约定：0 = Godot 4 Forward+ (Vulkan 反向 Z，raw [0,1]，近=1 远=0，天空=0)；
// 1 = OpenGL 风格 [-1,1]。uniform 在普通函数里可以正常读取。
float z_ndc_of(float raw_depth) {
	if (depth_convention == 1) {
		return raw_depth * 2.0 - 1.0;
	}
	return raw_depth;
}

void vertex() {
	// 无论网格多大/在何处，直接把顶点投到全屏 NDC（z 交给 depth_test_disabled 忽略）。
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
	v_proj = PROJECTION_MATRIX;
}

void fragment() {
	float ao = 0.0;
	float dbg_dist0 = 0.0;
	float dbg_dist1 = 0.0;
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	// 注意：Godot 4.7 的 fragment() 内不能使用 return（处理器函数限制），故用嵌套 if。
	if (raw_depth > 0.000001) {
		vec3 p = view_pos_z(INV_PROJECTION_MATRIX, SCREEN_UV, z_ndc_of(raw_depth));
		dbg_dist0 = -p.z;
		dbg_dist1 = -view_pos_z(INV_PROJECTION_MATRIX, SCREEN_UV, raw_depth * 2.0 - 1.0).z;
		float view_dist = -p.z;
		if (view_dist > 0.15 && view_dist < ao_max_dist) {
			// 视空间法线：相邻像素位置差叉乘。Godot 4.7 实测 fragment 无 SCREEN_PIXEL_SIZE，
			// 用 VIEWPORT_SIZE 取像素步长。
			vec2 px = 1.0 / max(VIEWPORT_SIZE, vec2(1.0));
			float dr = texture(depth_tex, SCREEN_UV + vec2(px.x, 0.0)).r;
			float dd = texture(depth_tex, SCREEN_UV + vec2(0.0, px.y)).r;
			float dl = texture(depth_tex, SCREEN_UV - vec2(px.x, 0.0)).r;
			float du = texture(depth_tex, SCREEN_UV - vec2(0.0, px.y)).r;
			// 四邻必须都有效（非天空）；否则当前像素在轮廓边上。
			if (dr > 0.000001 && dd > 0.000001 && dl > 0.000001 && du > 0.000001) {
				vec3 pr = view_pos_z(INV_PROJECTION_MATRIX, SCREEN_UV + vec2(px.x, 0.0), z_ndc_of(dr));
				vec3 pd = view_pos_z(INV_PROJECTION_MATRIX, SCREEN_UV + vec2(0.0, px.y), z_ndc_of(dd));
				vec3 pl = view_pos_z(INV_PROJECTION_MATRIX, SCREEN_UV - vec2(px.x, 0.0), z_ndc_of(dl));
				vec3 pu = view_pos_z(INV_PROJECTION_MATRIX, SCREEN_UV - vec2(0.0, px.y), z_ndc_of(du));
				// 轮廓/深度断裂处不施加 AO：视距跳变阈值随距离放宽（远处 1 像素覆盖更大世界距离）。
				float edge_thr = max(ao_radius * 2.0, view_dist * 0.05);
				float e1 = abs(-pr.z - view_dist);
				float e2 = abs(-pd.z - view_dist);
				float e3 = abs(-pl.z - view_dist);
				float e4 = abs(-pu.z - view_dist);
				if (e1 < edge_thr && e2 < edge_thr && e3 < edge_thr && e4 < edge_thr) {
					vec3 n = cross(pr - p, pd - p);
					float nl = length(n);
					if (nl > 1e-9) {
						n = n / nl;
						if (dot(n, normalize(-p)) < 0.0) {
							n = -n;
						}
						// 标准视空间半球 AO：在法线半球上取点 -> 用投影矩阵投到屏幕 -> 取场景深度重建视空间点
						// -> 若该方向上有明显更近的场景点（且深度差在局部半径内）则被遮挡。
						int samples = clamp(ao_samples, 4, 24);
						float occ = 0.0;
						float world_r = max(ao_radius, 0.05);
						vec3 tangent = normalize(cross(n, vec3(0.0, 1.0, 0.0) + vec3(0.0013, 0.0, 0.0)));
						vec3 bitan = cross(n, tangent);
						for (int i = 0; i < 24; i++) {
							if (i >= samples) {
								break;
							}
							float fi = float(i) + 0.5;
							float ang = fi * 2.39996323;
							float r0 = sqrt(fi / float(samples));
							// 余弦加权半球方向（z 轴朝法线）。
							float hz = sqrt(max(0.0, 1.0 - r0 * r0));
							vec3 dir = tangent * (cos(ang) * r0) + bitan * (sin(ang) * r0) + n * hz;
							float rr = world_r * (0.35 + 0.65 * fract(sin(fi * 78.233) * 43758.5453));
							vec3 sp = p + dir * rr + n * ao_bias;
							vec4 clip_s = v_proj * vec4(sp, 1.0);
							if (clip_s.w > 0.001) {
								vec2 suv = clip_s.xy / clip_s.w * 0.5 + 0.5;
								// 投影偏移上限：避免掠射角下采样点飞出几十像素造成脏边。
								if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0 && distance(suv, SCREEN_UV) < 0.30) {
									float ds = texture(depth_tex, suv).r;
									if (ds > 0.000001) {
										vec3 sq = view_pos_z(INV_PROJECTION_MATRIX, suv, z_ndc_of(ds));
										float diff = sq.z - sp.z; // >0: 场景点比采样点更靠近相机 -> 该方向被遮挡
										// 关键修复①：只接受深度差在局部半径内的遮挡（前景 9m 的窗棂不再压黑室内）。
										float lim = rr * 1.8 + ao_bias;
										if (diff > ao_bias && diff < lim) {
											float w = 1.0 - smoothstep(lim * 0.45, lim, diff);
											occ += w * clamp(diff / max(rr, 1e-4), 0.0, 1.0);
										}
									}
								}
							}
						}
						occ = occ / float(samples);
						// 关键修复③：温和映射，避免旧版 pow(occ*3.2, ...)*2.4 直接饱和成黑块。
						ao = clamp(pow(occ * 1.35, ao_contrast), 0.0, 1.0) * ao_strength;
						// 近裁剪面与远距离淡出，避免屏幕最外侧/远景被压黑。
						ao *= smoothstep(0.25, 1.2, view_dist);
						ao *= 1.0 - smoothstep(ao_max_dist * 0.6, ao_max_dist, view_dist);
					}
				}
			}
		}
	}
	if (ao_debug == 1) {
		// 调试：AO 值
		ALBEDO = vec3(ao);
		ALPHA = 1.0;
	} else if (ao_debug == 2) {
		// 调试：约定 0 的视距（/200m）
		ALBEDO = vec3(clamp(dbg_dist0 / 200.0, 0.0, 1.0));
		ALPHA = 1.0;
	} else if (ao_debug == 3) {
		// 调试：约定 1 的视距（/200m）
		ALBEDO = vec3(clamp(dbg_dist1 / 200.0, 0.0, 1.0));
		ALPHA = 1.0;
	} else if (ao_debug == 4) {
		// 调试：原始深度
		ALBEDO = vec3(clamp(raw_depth, 0.0, 1.0));
		ALPHA = 1.0;
	} else {
		// 纯乘法叠层：屏幕 = dst * (1 - ao)，alpha=0 处完全透传。
		ALBEDO = vec3(0.0);
		ALPHA = clamp(ao, 0.0, 1.0);
	}
}
