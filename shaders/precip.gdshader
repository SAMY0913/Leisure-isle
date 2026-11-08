shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// P8 阶段 6：雨/雪降水粒子（单个 GPUParticles3D 的 draw pass）。
// 为什么不用 StandardMaterial3D：需要两件它做不到的事——
//   1) 室内盒剔除：粒子世界位置落在小屋实体盒内时 discard，雨雪不穿屋顶/墙进屋；
//      相机在室内时也仍能从窗户看到屋外的雨雪（不是把整套粒子关掉）。
//   2) 世界空间绕 Y 朝向相机的公告板：雨丝必须保持竖直，雪片只需水平朝向相机。
// 粒子位置、速度、风向倾斜都由 ParticleProcessMaterial 负责，这里只做朝向/裁剪/着色。

uniform sampler2D albedo_tex : filter_linear, repeat_disable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float near_fade_start = 0.8;
uniform float near_fade_end = 3.4;

// 小屋实体盒（世界空间，yaw 对齐 AABB；与 g_occ_* 使用同一套数字，由 main 每帧写入）
uniform vec3 room_center = vec3(0.0, -999.0, 0.0);
uniform vec3 room_half = vec3(0.0);
uniform float room_yaw = 0.0;

varying vec4 v_color;
varying vec3 v_wpos;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 inst_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	float ang = atan(to_cam.x, to_cam.z);
	float c = cos(ang);
	float s = sin(ang);
	vec3 right = vec3(c, 0.0, -s) * inst_scale.x;
	vec3 up = vec3(0.0, inst_scale.y, 0.0);
	vec3 fwd = vec3(s, 0.0, c);
	// VERTEX 已经是世界坐标，MODELVIEW 只保留 VIEW：等价于把世界当模型空间。
	MODELVIEW_MATRIX = VIEW_MATRIX;
	VERTEX = center + right * VERTEX.x + up * VERTEX.y + fwd * VERTEX.z;
	NORMAL = fwd;
	v_wpos = center;
	v_color = COLOR;
}

void fragment() {
	vec4 tx = texture(albedo_tex, UV);
	float a = tx.a * albedo_color.a * v_color.a;
	// 贴脸淡出：避免近处粒子糊满屏幕
	float d = distance(v_wpos, CAMERA_POSITION_WORLD);
	a *= smoothstep(near_fade_start, near_fade_end, d);
	// 室内盒剔除（世界点绕 -yaw 旋回盒局部后与半尺寸比较，与 main._camera_inside_cottage 一致）
	vec3 lp = v_wpos - room_center;
	float cs = cos(-room_yaw);
	float sn = sin(-room_yaw);
	vec3 q = vec3(cs * lp.x - sn * lp.z, lp.y, sn * lp.x + cs * lp.z);
	if (abs(q.x) < room_half.x && abs(q.y) < room_half.y && abs(q.z) < room_half.z) {
		discard;
	}
	ALBEDO = tx.rgb * albedo_color.rgb * v_color.rgb;
	ALPHA = a;
}
