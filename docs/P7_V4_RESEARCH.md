# P7-V4 外部调研：角色外观设计原则、动画系统选型与移动导航方案

> 项目：休闲小岛幻境（P7-V4，岛民/NPC 阶段）
> 调研员：researcher（Team Lead：lead；共享任务 task-1）
> 工程基线：游戏工程 分支 p7-v4-islander，HEAD 1b59e59（P7-V3.2 冻结）；性能口径 P7_V32_REPORT.md
> 引擎：Godot 4.7.2 stable（Forward+，Windows x64）
> 抓取日期：**2026-10-21（+08:00）**（下文中所有 URL 均于该日实际抓取，结果逐条标注）
> 方法：web_fetch 抓公开正文；Godot 官方文档用 Sphinx 原始 RST（/en/4.7/_sources/...rst.txt）取全文，正文链接统一引 /en/4.7/ 页面；抓不到正文的 URL 在 §5.2 如实记录，**不作为结论依据**。
> 范围：只提炼设计原则与工程选型，**不复制任何外部资产、名称、贴图、几何或 UI 文案**；本文不含代码改动。

---

## 0. 结论先行

### 0.1 一句话结论

岛民角色用 **AnimationPlayer 承载全身关键帧剪辑**（Animation/AnimationLibrary 全部在代码中构造，零外部动画资产），**不引入 AnimationTree**；移动沿用工程已有的**步行图 + 地形高度函数（surface_y）的图驱动运动学**，**不引入 CharacterBody3D / navmesh / NavigationAgent3D**；角色身高沿用 1.50 m、头身比按任务书 4.2–5.0 头身，仅从动森/Dinkum 借「面部可读性、发型剪影、极简离散外观、外观与身体解耦」四类原则；在 V3.2 的 1838 draw call 基线上，把单角色 draw call 压在 40 以内（硬上限 56）。

### 0.2 四项选型表

| 决策点 | 结论 | 主要依据 |
| --- | --- | --- |
| 动画系统 | **AnimationPlayer**（代码构造 Animation + AnimationLibrary 全局库），自写状态机负责切换；**不用 AnimationTree**；程序化关节动画保留给 isle_cat、道具、以及必须与全身剪辑叠加的微动作 | Godot AnimationPlayer/AnimationMixer/Animation 文档（S7、S8、S16、S17）；AnimationTree 的「接管播放」Note（S9）；工程已有 isle_cat 程序化范式（游戏工程/scripts/isle_cat.gd） |
| 移动 | **图驱动运动学**：沿步行图节点/边插值移动，y 由 flat/stair/terrain 三种节点模式给出（楼梯在相邻踏面顶之间 lerp） | 工程无可行走碰撞体、已有权威步行图（游戏工程/scripts/isle_villager_spots.gd:3-24、:220-369）；world.surface_y（游戏工程/scripts/world.gd:293） |
| 导航/寻路 | 保留现有自写 A*（约 45 个节点，含室内/楼梯/花园）；**不烘焙 navmesh**；仅在节点数增长或需要权重/部分路径时迁移 AStar3D | 步行图现状（isle_villager_spots.gd:461、:504）；AStar3D 文档（S15）；NavigationMesh 默认参数与烘焙代价（S13、S14） |
| 角色比例 | 身高 1.50 m ±0.01（含发型最高点），**4.2–5.0 头身**（头含发 0.300–0.357 m），不照搬动森/Dinkum 的 2–3 头身 | 任务书（task-3）与真人尺度世界（门 1.14×1.94、室内净高 2.42、床 1.9）；外部参考仅用于面部/剪影原则（S1、S2、S3） |

### 0.3 本项目采用的可执行条款（P1–P14）

| 编号 | 条款（可执行） | 关键数值/做法 | 依据 |
| --- | --- | --- | --- |
| P1 | 身高与头身比锁定 | 1.50 m ±0.01，4.2–5.0 头身；头（含发）0.300–0.357 m；世界尺度不变 | 任务书；游戏工程/scripts/isle_scale_spec.gd:25-26；S1、S2、S3、S4 |
| P2 | 面部可读性下限 | 眼白宽 ≥ 头宽 1/6（约 0.045 m）；虹膜 0.028–0.035 m；嘴宽 0.09–0.11 m；鼻凸出 ≤0.03 m；五官集中在下半脸；9 m 机位截图可辨 | S2、S3（量测/目测） |
| P3 | 发型剪影差异 | V4 至少 2 款（短发/中长发）；最宽处 ≥ 头宽 1.06 倍；轮廓差 ≥0.03 m；只换 mesh 不动骨架 | S1、S2、S3；任务书 |
| P4 | 极简离散外观 | V4＝发型 2 款 × 共享发色 3–4 色＋固定服装；无滑杆、无体型、无数值输入；名称确认后不改；扩展顺序：眼型→肤色→服装色→饰品 | S1、S3、S5 |
| P5 | 外观与身体解耦 | 唯一骨架/关节长度/比例；换装只替换 MeshInstance3D 的 mesh 或材质参数；不改动画时长/相位/碰撞 | S1、S3 的选项清单；工程 BODY_R=0.20 |
| P6 | draw call 预算 | 单角色目标 ≤40 dc、任务书硬指标 ≤60 dc_est；材质 ≤3/角色、tris ≤5000；场景总 dc 目标 ≤1878（+40），硬上限 1894（V3.1 +5%）或 1929（V3.2 +5%，口径待 Lead 确认） | P7_V32_REPORT.md:26/293；Godot 逐 MeshInstance3D 绘制（工程统计口径） |
| P7 | 动画架构 | AnimationPlayer + 代码构造 Animation/AnimationLibrary；11 剪辑；不用 AnimationTree；无外部动画文件；blend 0.12–0.18 s（移动）/0.20–0.30 s（姿势） | S7、S8、S16、S17；S9 Note；S10 |
| P8 | 运动方案 | 图驱动运动学；walk 1.15 m/s、accel 6–8 m/s²、decel 10 m/s²、转身 6–8 rad/s；保持直立、不随坡倾斜 | isle_villager_spots.gd:3-24；S1/S3 观察 |
| P9 | 楼梯/斜坡 | 用 stair 节点在踏面顶 lerp（tread 01–16，rise 0.16375，landing 1.860）；上楼速度 0.8 倍；门廊台阶节点 0/0.14/0.28/0.42 已就绪 | 游戏工程/scripts/cottage.gd:291-292、:326、:1335-1485；isle_villager_spots.gd:10-13 |
| P10 | 导航 | 保留自写 A*（约 45 节点）；repath 仅在目标变更/卡住时；AStar3D 迁移触发：节点 >128 或需权重/部分路径；不用 navmesh/NavigationAgent3D | isle_villager_spots.gd:461/504；S12、S13、S14、S15 |
| P11 | 步行与速度匹配 | 参考速度 1.15 m/s、剪辑 0.96 s/循环、步幅 1.10 m（每步 0.55 m）；f＝v/S_cycle；speed_scale＝clamp(v/1.15, 0.85, 1.15)；脚滑 ≤0.03 m/步；不做 root motion | S7、S8；附录 A |
| P12 | 相机/可读性验收 | 默认 r=82 m 只验剪影/配色（角色约 21 px）；r=9 m 验面部（头约 43 px）；elev 默认 16.0°，范围 −25.2°…75.6° | 游戏工程/scripts/main.gd:67-69、:1315-1328；屏幕像素公式见附录 A |
| P13 | 暂停与时间同步 | 暂停时 AnimationPlayer 与移动同时停；恢复不跳变；不用常驻 Tween 做循环动作 | S8（callback_mode_process）；isle_cat.gd 的暂停经验 |
| P14 | 资产合规 | 不复制外部资产/名称/文本/UI/角色设计；只使用比例、选项结构、可读性等设计原则；全部几何/材质程序化生成 | S1、S2、S3、S5 |

---

## 1. 动森 / Dinkum 的角色设计原则

### 1.1 抓取情况

| 来源 | URL | 抓取日期 | 结果 |
| --- | --- | --- | --- |
| 任天堂官方支持：动森新地平线「如何开始新游戏」 | https://en-americas-support.nintendo.com/app/answers/detail/a_id/49116/p/988 | 2026-10-21 | HTTP 200；HTML 被截断在 100000 字符，但角色创建段落完整可取（标题：How to Start a New Game (Animal Crossing: New Horizons)） |
| 动森官方商店页（8 张官方角色立绘） | https://www.nintendo.com/us/store/products/animal-crossing-new-horizons-switch/ | 2026-10-21 | HTTP 200；页面含 character-1-outfit.png … character-8-jog.png；实际取 dpr_2.0 版本（248×436、236×413）做轮廓量测 |
| Dinkum Steam 公告「Character Customisation: How to express yourself on the Island」 | https://store.steampowered.com/news/posts/?appids=1062520&enddate=1656669915&feed=steam_community_announcements | 2026-10-21 | HTTP 200；正文完整（46810 字符）；发布日期 24 Jun, 2022 |
| Steam AppDetails（Dinkum 截图/简介） | https://store.steampowered.com/api/appdetails?appids=1062520&l=english | 2026-10-21 | HTTP 200 JSON；15 张截图；简介确认是岛屿生活模拟 |
| 3DM 中文攻略（Dinkum 改脸限制，2022-09-05，EA 期） | https://www.3dmgame.com/gl/3859001.html | 2026-10-21 | HTTP 200；正文完整；明确「目前只能换头发，无法支持整容」 |

补充抓取失败/不可达的来源见 §5.2（Nookipedia 503、VG247 正文被内联 CSS 占满、Fandom fetch failed、Steam News API 超时等），均不作为依据。

### 1.2 头身比例：外部 2–3 头身，本项目 4.2–5 头身的取舍

**外部量测/目测（非官方数值，仅作比例参考）**

| 作品 | 头身比 | 方法 | 备注 |
| --- | --- | --- | --- |
| 动森：新地平线 | 约 1.9–2.1 头身（含发型体积） | 官方促销立绘（S2）alpha 轮廓量测：全身高 436 px，头+发轮廓到约 52% 处，颈/下颌最窄处宽 111 px；头发最宽约 216 px | 促销立绘不是实机模型，实机可能略高；头部明显大于写实比例 |
| Dinkum | 约 2.5–3 头身（目测） | 官方 Steam 截图（S4，高角度俯视，纵向透视压缩）与商店 capsule 宣传画 | 截图量测会失真，仅作量级参考；其相机角度与本项目轨道相机相似 |
| 本项目 V3.2 人体参照 | 8.3 头身（0.18 m 头 / 1.50 m 身高） | 游戏工程/scripts/isle_scale_figure.gd:21、:85 | 写实比例，作为尺度审计参照，不是 V4 角色 |

**本项目取 4.2–5.0 头身的原因**（任务书 task-3 已定，本文按此写并说明取舍）：

1. 世界是真人尺度：门洞净宽 1.14 m、净高 1.94 m（游戏工程/scripts/cottage.gd:9），室内净高 2.42 m，床约 1.9 m 长，室内家具均为真人尺度。若取动森式 2 头身，1.50 m 身高的头会达约 0.75 m，坐床、进门、坐椅都会产生明显的尺度荒诞感；4.2–5 头身对应头（含发）0.300–0.357 m，与门/床/椅的关系合理。
2. 相机距离决定可读性：默认轨道半径 82 m、垂直 FOV 42°、1600×900 下，1.50 m 角色只有约 21 px 高；只有拉近到最小半径 9 m 时角色约 195 px、头约 43 px。也就是说，**默认视角读的是剪影与配色，近景才读脸**；动森式大头在默认视角并不会额外增加信息量，反而牺牲近景的身体比例。
3. 动森/Dinkum 的比例与其「整个世界一起缩小」的美术体系绑定；本项目世界已是真人尺度且 V3.2 尺度规范冻结（WORLD_SCALE_SPEC.md），改世界尺度的成本远高于改头身比。

**可执行结论**：沿用 1.50 m 总高与 4.2–5 头身；外部 2–3 头身只用于推导「面部可读性、发型剪影、外观解耦」原则，**不照搬比例数值**。

### 1.3 面部可读性（从动森/Dinkum 提炼，不复制其画风）

动森官方创建说明强调「Adjust your character's appearance in whatever way you'd like」，且所有特征（如发型）与初始二选一的「style」无关（S1）。其立绘（S2）可观察到的可读性手法：

- 眼睛极大且高对比：眼白面积大，虹膜与眼白、皮肤形成 3 级明度差；眼睛位于面部视觉中心偏下。
- 五官集中在下半脸：鼻子几乎不凸出（仅一个小色块/小楔形），嘴小而位置明确；面部上半部留给眼睛，下半部留嘴与下巴。
- 面部前平面完整：脸颊、眼、嘴都在头部最前投影附近，侧看不会出现五官凹陷。
- 头部轮廓圆润、无复杂结构；头发包住头骨形成第二层轮廓。

Dinkum 的创建公告（S3）把可定制项写成 5 类：肤色、头发、眼睛、鼻子与嘴唇形状、上衣颜色——即**眼、鼻、嘴是离散预设，而不是可拖动的面部骨骼**。这与我们的低模程序化方案一致：用少量几何 + 颜色预设表达五官，不做面部骨骼绑定。

**本项目可执行的面部指标**（与 4.2–5 头身匹配）：

| 部位 | 建议数值（头含发高 0.300–0.357 m，头宽 0.26–0.30 m） | 验收 |
| --- | --- | --- |
| 眼白宽 | ≥ 头宽 1/6，即 0.045–0.052 m | r=9 m、1600×900 截图（头约 43 px）双眼可辨、虹膜可辨 |
| 虹膜直径 | 0.028–0.035 m（约眼白 60–70%） | 同上 |
| 双眼间距 | 约 1 个眼白宽（0.045–0.05 m） | 正视截图 |
| 眉 | 长 0.05 m、厚 0.014 m，位于眼上 0.03–0.04 m | 近景可辨 |
| 鼻 | 凸出 ≤0.03 m、宽 0.03–0.04 m，仅作小楔形/色块 | 侧视不破坏面部平面 |
| 嘴 | 宽 0.09–0.11 m、高 0.02–0.03 m | 近景可辨 |
| 耳 | 宽 0.035–0.045 m，位于头侧中线偏后 | 侧视可辨 |
| 五官垂直分布 | 眼睛中心约在头高 45% 处（自头顶向下），嘴在 70% 附近 | 近景正视 |

注意：**默认 82 m 视角下眼睛只有约 0.7 px、嘴约 1.5 px**，面部细节在默认视角完全不可见（见 §3.8）。因此面部指标只在近景验收；默认视角的资源优先级应给剪影与配色。

### 1.4 发型与剪影

- 动森：发型是最大的身份识别变量之一；官方支持页明确「All character features (like hairstyles) are available regardless of which picture you choose to begin with」，且游戏推进后可随时改变外观（S1）。立绘里头发体积几乎包住整个头部（发宽 216 px vs 头宽约 200 px，S2 量测），形成强剪影。
- Dinkum：发型/发色在 Sally 的美容沙龙修改，衣服/帽子/靴子/眼镜在 Clover 的 Threadspace 购买（S3）；即**外观中「轮廓类」和「颜色类」分开在不同系统里长期开放**。

**本项目可执行原则**：

1. V4 至少 2 款发型（1 短发 + 1 中长发；任务书要求），共享发色 3–4 色；后续每增加一款发型，必须改变外轮廓，而不是只换贴图。
2. 剪影指标：发型最宽处 ≥ 头宽 1.06 倍（约 0.28–0.32 m），或顶部比基础头骨高 ≥0.03 m；任意两款发型的 alpha 轮廓差异 ≥0.03 m 的局部宽度差。
3. 默认 82 m 截图（角色约 21 px）中，两款发型必须仍能区分；这是剪影验收的最低门槛。
4. 发型只替换 hair 节点的 MeshInstance3D 网格，不改变骨架、关节长度、动画轨道与身体比例；切换后除 hair 外所有关节世界变换差 <1e-4 m（任务书探针要求）。

### 1.5 极简外观选择方式

**动森（S1）**：
- 开局「Choose your style」二选一只是**起手样式**，不是性别/体型锁定；原文「choose either picture to get started. Adjust your character's appearance in whatever way you'd like」，并且「All character features (like hairstyles) are available regardless of which picture you choose to begin with」。
- 游戏推进后可随时改变外观：「Once you've played through the game for a bit, you will be able to change your character's appearance whenever you'd like to.」
- 不可改的是身份信息：「Character names, island names, and birthdays cannot be changed after you confirm them.」

**Dinkum（S3、S5）**：
- 创建时 5 类离散选项：肤色、头发、眼睛、鼻子与嘴唇形状、上衣颜色；每类「a few options」，并提供 Randomise 按钮随机生成。
- 创建后：发型/发色可在沙龙改（花 Dinks），衣服/帽子/靴子/眼镜可购买更换；但 2022 EA 期的中文资料说明脸不能改，只能换发型（S5，时效风险见 §6）。
- 未提及身高、体型、四肢比例选项。

**提炼的设计原则**：

1. **离散预设，不设滑杆**：每类 4–8 个离散选项；面部与身体不做数值化捏脸。原因：低模程序化几何下，离散预设可枚举、可测试、无极端值穿模；两作均采用离散选项（S1、S3）。
2. **一次选择 + 长期可改的渠道**：创建界面只做最小选择；后续通过镜台/衣柜/沙龙等场景化入口修改，把外观变更变成「生活内容」而不是菜单功能（S1、S3）。
3. **身份信息锁定、外观不锁**：名称此类身份信息确认后不改（S1）；外观（尤其发型/服装）长期开放。
4. **随机按钮**：用于演示/QA/惊喜，不作为主路径；Dinkum 提供 Randomise（S3），本项目可在调试面板提供。
5. **V4 的最小可行集**：发型 2 款 × 共享发色 3–4 色 + 固定服装（任务书：白色内衬衣 + 绿色农夫连体防水背带裤）。扩展顺序：眼型 → 肤色 → 服装色 → 饰品；每加一类都保持离散、可枚举、无滑杆。

### 1.6 外观与身体比例解耦

两作的公开创建说明中，可调项均为面部/发型/服装/颜色，未提及身高/体型/肢体比例（S1、S3）；因此可提炼为：**外观系统与身体比例、骨架、碰撞体解耦**。结合本项目：

- 唯一骨架、唯一关节长度、唯一身体半径：工程步行图已用 BODY_R = 0.20 m 做家具/边界净距（游戏工程/scripts/isle_villager_spots.gd:24），换装不得改变该半径；若未来做物理胶囊，建议 r=0.22–0.24（略大于 BODY_R，留视觉余量）。
- 换装只允许替换 MeshInstance3D 的 mesh、材质参数/颜色，或添加挂点装饰；不得改动画剪辑时长、关节轨道、脚底到头顶的总高。
- 验收：同一角色两款发型切换后，除 hair 相关节点外，所有关节世界坐标、AABB 高度、脚底 y 的差 ≤0.01 m（任务书探针已要求「除发型外度量一致」）。

### 1.7 合规红线：只提炼原则，不复制资产

- 不复制动森/Dinkum 的任何几何、贴图、材质、名称、UI 文案、角色设计、配色组合；不使用其角色剪影做参照建模。
- 本文只提炼以下不受版权保护的设计原则：比例关系、可读性阈值、离散选项结构、外观-身体解耦、长期修改渠道。
- 所有角色几何/材质由本项目程序化生成（SurfaceTool / toon_material 体系），颜色用本项目色板；外部 URL 仅作设计依据引用（S1、S2、S3、S4、S5）。

---

## 2. 动画系统选型：AnimationPlayer vs AnimationTree vs 纯程序化

### 2.1 官方事实（Godot 4.7）

**AnimationPlayer（S7、S8）**
- 官方描述：用于通用动画播放，包含 AnimationLibrary 资源字典与自定义混合时间；「AnimationPlayer is better-suited than Tween for more complex animations, for example ones with non-trivial timings」；「Updating the target properties of animations occurs at the process frame.」
- 关键属性/方法：play(name="", custom_blend=-1, custom_speed=1.0, from_end=false)；seek(seconds, update=false, update_only=false)；speed_scale（1 正常、0.5 半速、2 双速、负值倒放、0 不推进）；playback_default_blend_time 默认 0.0；current_animation / assigned_animation。
- 继承 AnimationMixer：add_animation_library(name, library)；文档明确「AnimationMixer has a global library by default with an empty string as key」，并给出 get_animation_library("").add_animation("animation_name", animation_resource) 的用法；callback_mode_process 默认 1（IDLE）；root_motion_track 默认空；animation_finished 信号对循环动画不发出。

**Animation（S16）与 AnimationLibrary（S17）**
- Animation 可完全在代码中构造：add_track(Animation.TYPE_VALUE) → track_set_path(track_index, "Enemy:position:x") → track_insert_key(track_index, time, value) → length；length 默认 1.0，loop_mode 默认 0（LOOP_NONE），step 默认 0.033333335。
- AnimationLibrary.add_animation(name, animation) 返回 Error；get/has/remove_animation 可用。也就是说：**不产生 .tres/.anim 文件，也能在运行时组装出完整剪辑库**。

**AnimationTree（S9、S10）**
- 官方描述：「A node used for advanced animation transitions in an AnimationPlayer.」
- 关键 Note：「When linked with an AnimationPlayer, several properties and methods of the corresponding AnimationPlayer will not function as expected. Playback and transitions should be handled using only the AnimationTree and its constituent AnimationNode(s). The AnimationPlayer node should be used solely for adding, deleting, and editing animations.」——即引入 AnimationTree 后，播放/过渡的控制权整体转移给它。
- 需要额外资源（AnimationNodeStateMachine/BlendTree/BlendSpace 资源）与树内参数；教程指出状态机过渡有 Xfade Time/Curve、Advance Condition/Expression（Advance Condition 只能检查 true，不能检查 false；Advance Expression Base Node 默认指向 AnimationTree 自身，需改指到存变量的脚本节点）；状态机 travel 用 A*。
- 适合：分层混合（上下半身）、BlendSpace 连续速度混合、大量状态自动过渡、root motion 与状态机整合。

**纯程序化关节动画（工程内已有范式：游戏工程/scripts/isle_cat.gd）**
- 每帧直接写关节 transform；可精确控制呼吸/眨眼/尾巴/耳朵；暂停行为与 SceneTree 一致（PROCESS_MODE_INHERIT）；探针可 set_process(false) 后手动 advance() 摆姿势；无任何动画资源。
- 代价：走/坐/躺等姿势过渡需要手写曲线与状态机；无法可视化编辑；复杂动作（sit_down/lie_down/get_up）手写关键帧成本高于 Animation 资源；不能直接复用动画编辑器。

### 2.2 本项目约束

1. 全程序化建模、无外部资产（任务书）；角色由代码生成 MeshInstance3D 挂在关节 Node3D 上，无 Skeleton3D。
2. 资源最少化：不应为岛民引入 .tscn/.tres/.anim 资产；动画应随脚本生成。
3. draw call 基线 1838（V3.2，P7_V32_REPORT.md:293），V3.1 为 1804；动画系统本身不增加 draw call，但角色网格件数增加。
4. 现有 isle_cat.gd 已经验证「程序化关节 + 呼吸/眨眼/状态 + 暂停接口」范式，可复用其暂停/调试经验。
5. 任务书要求 11 个剪辑（idle_breath、idle_look、blink、walk、eat_loop、sit_down、sit_idle、stand_up、lie_down、sleep、get_up），且明确「切线平滑、切换用 blend、不常驻 Tween」——这正是 Animation 资源 + AnimationPlayer 的强项。

### 2.3 三方案对比

| 维度 | AnimationPlayer（代码构造 Animation） | AnimationTree | 纯程序化关节动画 |
| --- | --- | --- | --- |
| 外部资源 | 0（全部代码构造） | 需树资源（StateMachine/BlendTree 等） | 0 |
| 关键帧/姿势质量 | 高，可逐关节打关键帧、切线可控 | 高，且能做分层/混合 | 中，复杂姿势需手写曲线 |
| 状态切换 | 脚本调 play(name, blend) + 自写状态机 | 树内状态机自动过渡 | 自写状态机 |
| 上下半身分层/速度连续混合 | 不支持（需多 AnimationPlayer 或程序化叠加） | 支持（BlendTree/BlendSpace） | 可手写混合，成本高 |
| 暂停/时间同步 | 跟随 SceneTree.paused；可设 callback_mode_process | 同样跟随 | 跟随（PROCESS_MODE_INHERIT） |
| 运行时成本 | 只更新当前剪辑轨道（低） | 更新树中活跃节点/混合（略高） | 每帧写关节（与剪辑数无关，低） |
| 对程序化建模的适配 | 好：轨道路径指向关节 Node3D | 一般：树资源不便于代码生成 | 好：直接写关节 |
| 本项目的合适度 | **高（主选）** | 低（当前不需要） | 中（猫/道具/叠加层） |

### 2.4 选型结论与落地方式

**结论：AnimationPlayer 作为唯一全身剪辑播放器；AnimationTree 不引入；程序化动画保留用于 isle_cat、环境道具、以及需要与全身剪辑同时叠加的微动作（look-at、程序化眨眼——若不做独立面部 AnimationPlayer）。**

落地方式（供 modeler/工程实现参考）：

1. 在角色根节点下创建 AnimationPlayer（代码 new），root_node 指向模型根（AnimationMixer.root_node；旧 AnimationPlayer.root_node 已 deprecated）。
2. 对每个剪辑：Animation.new()；对每个关节加 TYPE_ROTATION_3D 轨道（旋转用四元数关键帧；必要时加 root 的 TYPE_POSITION_3D 做蹲/坐/躺的根位移），track_set_path 用相对 root_node 的路径（例如 pelvis/torso/neck/head）；track_insert_key 打关键帧；设置 length、loop_mode。
3. 把所有剪辑放进 AnimationLibrary，通过角色 AnimationPlayer 的全局库挂载（get_animation_library("")），或 add_animation_library；不需要保存任何文件。
4. 状态机（walk/idle/sit/lie/eat/sleep 等）由岛民驱动脚本维护；切换时 play(name, custom_blend)，或设置 playback_default_blend_time 后 play(name)。移动/姿势切换 blend 建议：移动间 0.12–0.18 s；站立↔坐/躺 0.20–0.30 s。
5. 速度匹配用 AnimationPlayer.speed_scale（见 §3.6）；暂停/恢复由 SceneTree 暂停自动生效；不要用常驻 Tween 做循环动作（与任务书一致）。
6. 若 idle 时必须自动眨眼且 idle_breath 同时播放：两个方案——(a) 单独一个只含眼睑 scale 轨道的 face AnimationPlayer（成本 1 个节点、极低 CPU）；(b) 在驱动脚本里程序化眼睑（复用 isle_cat 的 blink 计时器）。任务书的 blink 剪辑可保留用于 QA/整段表演，不一定常驻播放。

### 2.5 11 个剪辑的建议时长与循环

任务书要求标注时长与循环，以下是建议值（以 1.15 m/s 行走参考速度设计）：

| 剪辑 | 建议时长 | 循环 | 说明 |
| --- | --- | --- | --- |
| idle_breath | 3.2 s | 是 | 胸腔/脊柱 0.5–1.5°、肩 1–2 mm 的呼吸；幅度小，避免与 look 冲突 |
| idle_look | 4.0 s | 是 | 头 yaw ±10–12°，2–3 个关键帧，中段回正 |
| blink | 0.18 s | 否 | 眼睑 scale y 1→0.15→1；切线平滑；若叠加播放见 §2.4 第 6 条 |
| walk | 0.96 s | 是 | 参考速度 v_ref=1.15 m/s、步幅 S_cycle=1.10 m（每步 0.55 m）；见 §3.6 |
| eat_loop | 2.4 s | 是 | 一次「叉到嘴—咀嚼—放下」2.4 s；配合 eat 座位/桌子高度（座面 0.97 局部） |
| sit_down | 1.1 s | 否 | 站立→坐姿；根位移从脚锚点到座面锚点由驱动脚本 tween，剪辑只做关节姿势 |
| sit_idle | 4.0 s | 是 | 坐姿呼吸/轻微重心变化 |
| stand_up | 0.9 s | 否 | 坐姿→站立；与 sit_down 反向、但不要简单倒放（重心路径不同） |
| lie_down | 1.4 s | 否 | 站立→卧姿；根锚点到床垫锚点由驱动脚本 tween |
| sleep | 6.0 s | 是 | 卧姿呼吸，幅度更小、频率更低（约 0.2 Hz） |
| get_up | 1.2 s | 否 | 卧姿→站立；先侧身再起，避免直接平移 |

以上时长是建议起点，modeler 可按动作表演微调，但**walk 必须与 v_ref 绑定**，否则脚滑验收会失败（见 P11）。

### 2.6 与纯程序化/现有 isle_cat 的关系

- isle_cat.gd 已证明程序化动画在本工程可维护、可暂停、可探针驱动；其呼吸/眨眼/尾巴/耳朵的写法可复用到角色面部叠加层。
- 角色全身动作（走/坐/躺/吃/睡）用 AnimationPlayer，而不是程序化：这些动作有明确起止姿势与长时间静止段，用关键帧表达更省代码、更易调、更易做探针时长断言。
- 两者边界：AnimationPlayer 管「身体剪辑」；程序化层管「与身体剪辑并行的微动作」（如 look-at 目标、眼睑眨动）；二者不要写同一关节的同一属性（避免叠加冲突）；若必须叠加，程序化层只写 head/eyes 的增量。

### 2.7 何时升级到 AnimationTree（触发条件）

只有出现以下任一需求才引入 AnimationTree：
1. 需要上下半身分层（走路同时挥手/吃东西）或 BlendSpace 连续速度混合（walk↔run 连续过渡）；
2. 需要状态机自动过渡（Advance Condition/Expression）且状态数 >25；
3. 需要 root motion 与状态机深度整合（本项目明确不用 root motion，见 §3.6）；
4. 剪辑数量与混合需求增长到自写状态机难以维护。

升级时必须整体迁移播放控制（S9 的 Note）：不能再一部分用 AnimationPlayer.play、一部分用树。

---

## 3. 移动、导航与步行匹配

### 3.1 本项目现状：没有可行走碰撞体，已有权威步行图

- 工程唯一存在的碰撞体是点击检测用 hitbox：StaticBody3D，collision_layer=2、collision_mask=0，BoxShape3D（游戏工程/scripts/isle_math.gd:452-461）；只在 cottage.gd:106-107 用于 DoorHit（2.0×2.6×1.4）与 ChimneyHit，用于点击开门/烟囱检测，不是可行走碰撞。
- 步行图文件头注释明确：「No physics colliders exist in this project, so this graph is the single source of truth for where the villager may stand.」（游戏工程/scripts/isle_villager_spots.gd:3-8）。
- 步行图已有约 45 个节点（NODE_DEFS :26）、边（EDGE_DEFS :79）、11 个座位（SEAT_DEFS :131）、7 个观景点（VIEW_DEFS :146）、床（BED :156）；build() :220 从真实 cottage 变换生成世界坐标；楼梯节点 tread_01..tread_16 与 landing 由 cottage.get("stairs") 生成（isle_villager_spots.gd:220-369）。
- 高度来源三种模式：flat（y 已是行走面）、stair（y 是踏面顶，段内 lerp）、terrain（每帧跟 W.surface_y）；world.surface_y = 地形高度 + 3 个草丘（游戏工程/scripts/world.gd:270-298）。
- 寻路：自写 A*（isle_villager_spots.gd:461），最近节点用「水平距离 + |dy|*2」（:504）；边净距用 BODY_R=0.20（:24、:429-430）。

### 3.2 方案对比：物理 CharacterBody3D vs 图驱动运动学（推荐后者）

| 维度 | A. CharacterBody3D + 碰撞体 | B. 图驱动运动学（推荐） |
| --- | --- | --- |
| 是否需要新建碰撞 | 是：地形 HeightMap/三角面、墙、楼梯、门框等；工程当前为零 | 否：步行图就是可行走域 |
| 上下楼梯 | 需要隐形斜坡或逐级 step-up；0.16375 m 垂直面会被当作墙 | 直接用 stair 节点踏面顶 lerp，天然平滑 |
| 贴地/斜坡 | move_and_slide + snap + floor_max_angle 自动处理 | 每帧 y=surface_y（terrain）或节点 y（flat/stair），无抖动 |
| 与家具/座位衔接 | 需额外碰撞/触发 | 座位/床已有锚点与 approach 逻辑（isle_villager_spots.gd:18-20） |
| 运行时成本 | 物理服务器 + 碰撞形状维护 | 纯数学，极低 |
| 可控/可测 | 物理抖动、snap 参数需调 | 确定性，探针易断言 |
| 适合场景 | 玩家操控角色、可推动物体、动态障碍 | 单个 NPC 的固定生活路线（本项目现状：lone islander） |

**结论：V4 用 B。** 步行图已经覆盖户外道路、门廊台阶、一层房间、楼梯、阁楼、座位/床/观景点，且明确声明它是唯一权威；再建一套物理碰撞既重复又与现有尺度审计脱节。

图驱动运动学的执行细节（建议）：

1. 每个移动段是一条图边（两个节点）；位置沿边按速度推进，朝向取边方向水平投影；到节点后取下一段。
2. y 取值：terrain 节点每帧 W.surface_y(x,z)；flat 节点固定 y；stair 边在两端踏面顶 y 之间按水平进度 lerp（例如 tread_01→tread_02 从 fy+0×0.16375 到 fy+1×0.16375）。
3. 移动速度：walk 1.15 m/s；楼梯段 0.8 倍（约 0.92 m/s，符合上楼变慢的直觉）；accel 6–8 m/s²、decel 10 m/s²；到点前按 decel 减速，避免急停。
4. 转身：yaw 朝边方向 lerp，角速度 6–8 rad/s；接近目标朝向时若差值 <0.05 rad 直接吸附。
5. 不做重力/跳跃：全程贴图行走；跳跃既无输入动作（project.godot 仅有 fly_* 动作），也无 jump 剪辑，V4 不需要。
6. 座位/床：由 spot 逻辑把根从站立锚点 tween 到座面/床垫锚点，同时播放 sit_down/lie_down；不要用 root motion 做这段位移（见 §3.6）。

### 3.3 CharacterBody3D 官方行为与参数（备选/未来玩家角色）

若未来要加玩家操控角色，需要先补一套可行走碰撞（地形、房屋墙、楼梯、门框）。以下官方行为与参数可作为实现依据（S6）：

| 属性/方法 | 默认值 | 官方说明要点 | 本项目建议 |
| --- | --- | --- | --- |
| motion_mode | 0（GROUNDED） | 地面模式 | 保持默认 |
| up_direction | (0,1,0) | 用于判定 floor | 保持默认 |
| floor_max_angle | 0.7853982 rad（45°） | 超过该角度的斜坡视为墙/天花板 | 45°；与 world._slope_ok（ny≥约 0.72，≈44°）一致 |
| floor_snap_length | 0.1 m | 非 0 时贴地；竖直上升速度存在时不 snap（可跳离地面） | 0.20 m（>楼梯 0.16375 m，也 >门廊 0.14 m） |
| floor_constant_speed | false | false 时下坡快、上坡慢；true 时地面恒速，但必须配合 snap 才能贴住下坡 | true（角色移动更可控），配 snap 0.20 |
| floor_stop_on_slope | true | 斜坡上停住不滑 | 保持 true |
| get_floor_normal / get_floor_angle | — | 只有在 move_and_slide() 之后且 is_on_floor() 为 true 时有效；碰撞法线不一定等于表面法线 | 不要用碰撞法线当美术贴地法线 |
| apply_floor_snap | — | 手动贴地；已在地面时无效果 | 传送/落位后调用一次 |
| move_and_slide | — | 应在 _physics_process 中调用；自动用物理步长 delta；返回是否碰撞；碰撞后修改 velocity | 唯一移动入口 |
| safe_margin | 0.001 | 碰撞安全边距 | 默认 |
| max_slides | 6 | 滑动迭代上限 | 默认 |

物理方案附加要求：

- 胶囊：身高 1.50 m，建议 CapsuleShape3D 总高 1.46 m、半径 0.22–0.24 m（脚底 y=0 时形状中心 y≈0.73 m）；与 BODY_R=0.20 的图净距语义兼容。
- 重力：建议 20 m/s²（游戏手感，而非 9.8）；若保留跳跃，跳速约 4.7 m/s 对应约 0.55 m 跳高；V4 不需要跳跃。
- 楼梯：CharacterBody3D 不会自动上 0.16375 m 的垂直台阶；必须加隐形斜坡碰撞（见 §3.4）。
- 门廊台阶 0.14 m 同理，也需要斜坡或台阶碰撞。

### 3.4 楼梯与斜坡处理

**本项目（图驱动方案）**：楼梯已经是图的一部分（tread_01..16，rise 0.16375，landing top 1.860，cottage.gd:291-292、:326；楼梯几何 cottage.gd:1335-1485）；stair 模式在相邻踏面顶之间 lerp，等于把 16 级台阶解析成连续斜面（数学上等价于坡道），不需要任何碰撞与 step-up 逻辑。验收：相邻 stair 节点 y 差 = 0.16375；段内 y 随水平进度线性变化；脚底贴地误差 ≤0.01 m；无瞬移（每帧 |Δy| ≤ 0.16375×速度/段长）。

**未来物理方案（备选）**：为每段楼梯加 1–2 个隐形 BoxShape3D 斜坡（厚度 0.05 m，宽度 0.85 m），碰撞层与地面一致，仅碰撞不渲染：

- 楼梯 A 段：8 级 × rise 0.16375 = 1.310 m，run 8×0.26 = 2.08 m → 坡角 atan(1.310/2.08)=32.2°（<45°，可走）；
- 楼梯 B 段同理 32.2°；中间平台保持水平；
- 门廊 3 级台阶：rise 0.14×3=0.42 m，run 0.30×3=0.90 m → 坡角 atan(0.42/0.90)=25.0°（<45°，可走）。
- 若用 floor_max_angle=45°，两段坡道都能被识别为 floor；snap 0.20 m 保证下坡贴地。

### 3.5 导航：为什么不用 navmesh / NavigationAgent3D

- 当前世界是静态小岛（海岸线最大直径约 63.6 m）、无动态障碍、无可行走碰撞、步行图已手工覆盖生活路线；烘焙 navmesh 只会引入一套与步行图重复的数据。
- NavigationAgent3D 官方说明：需要导航数据（navmesh）才能工作；设置 target_position 后必须每 physics 帧调用 get_next_path_position() 更新内部路径逻辑；导航系统从不移动父节点，移动完全由脚本负责；avoidance_enabled 默认 false，且「Avoidance processing with many registered agents has a significant performance cost and should only be enabled on agents that currently require it.」（S11、S12）。
- 若未来使用 navmesh：NavigationMesh 默认 agent_height=1.5、agent_max_climb=0.25、agent_radius=0.5、cell_size=0.25、cell_height=0.25（S13）；agent_radius 0.5 大于本项目 BODY_R 0.20，需下调到 0.20–0.24 重新烘焙；agent_height 1.5 恰好等于角色总高；agent_max_climb 0.25 > 楼梯 0.16375，可跨台阶；cell_size 0.25 与踏步 0.26 太接近，烘焙楼梯会不稳定，需下调到 0.10–0.13，但官方警告过小的 cell 可能造成卡死甚至崩溃（S14）。
- 结论：V4 不引入；升级条件：NPC 数量 >12、需要动态避障/移动障碍、或世界出现大量程序化不可步区域。

**AStar3D 升级条件**（当前自写 A* 足够）：官方 AStar3D 需手动 add_point/connect_points，可重写 _compute_cost/_estimate_cost，add_point 的 weight_scale 乘 _compute_cost 结果（越低越优），get_point_path 返回 PackedVector3Array，allow_partial_path=true 且目标 disabled 时可能搜索很久（S15）。当节点数 >128、或需要 partial path/权重/非欧氏代价时，用 AStar3D 替换自写 A*，节点数据可从现有 graph 直接迁移。

### 3.6 原地步行动画与移动速度匹配

**核心公式**（推导见附录 A）：

- 每循环步幅 S_cycle = 2 × 单步长；本项目建议单步 0.55 m → S_cycle = 1.10 m；
- 步频 f = v / S_cycle；相位角速度 ω = 2π f；
- 剪辑参考速度 v_ref = S_cycle / T_clip；walk 剪辑 T_clip=0.96 s → v_ref = 1.10/0.96 ≈ 1.15 m/s；
- 播放速度 speed_scale = v / v_ref；建议 clamp 0.85–1.15，避免过快/过慢导致姿势失真；
- 脚滑速率 = |v − speed_scale × v_ref|；验收目标 ≤0.03 m/步（视觉不可察）。

**匹配方式**：

1. NPC 行走速度定为 1.15 m/s；walk 剪辑 0.96 s，则正常播放 speed_scale=1.0，无脚滑。
2. 若某段路需要更慢/更快（如楼梯 0.92 m/s），speed_scale = 0.92/1.15 = 0.80（在 0.85 下限附近，可接受；或把楼梯速度定为 0.98 m/s → speed_scale 0.85）。
3. idle↔walk：blend 0.15 s；walk 起步时相位从当前帧继续，不重置为 0（避免起步时脚突然抽一下）；停下时相位继续走到最近的支撑相位再 blend 到 idle（简单实现可容忍微小脚滑）。
4. 姿势切换（sit_down/stand_up/lie_down/get_up）：blend 0.20–0.30 s；根位移由 spot tween 完成，剪辑只做关节姿势，避免 root motion 与脚本移动双写。
5. 不做 root motion：官方文档说明 root motion 轨道（TYPE_POSITION_3D/TYPE_ROTATION_3D/TYPE_SCALE_3D）会让变换「visually canceled, animation appears to stay in place」（S8）；本项目的位移由步行图驱动，动画必须原地，否则双重位移。

### 3.7 转向、贴地与暂停

- 转向：yaw 朝移动方向 lerp（6–8 rad/s），不随地形倾斜；动森/Dinkum 的角色在坡上保持直立（截图观察 S2、S4；非官方数值），直立也能保证面部在低角度相机下可读。
- 贴地：terrain 节点每帧 W.surface_y；stair 边 lerp；flat 节点固定 y；脚底与行走面误差 ≤0.01 m。
- 暂停：岛民驱动 _process 与 AnimationPlayer 都受 SceneTree.paused 控制；暂停时位置与动画位置都不前进，恢复不跳变（isle_cat.gd 的 PROCESS_MODE_INHERIT + 时间累加器经验可复用）。AnimationMixer.callback_mode_process 默认 IDLE；若未来移动改到物理帧，再把动画回调切到 PHYSICS 以同步。

### 3.8 相机与角色可读性距离

工程相机参数（游戏工程/scripts/main.gd:67-69、:1315-1318、:1328；isle_math.gd:40）：默认半径 82 m、FOV 42°（垂直）、near 0.3、far 2200；滚轮缩放 9.0–240.0 m；elev 默认 0.28 rad（16.0°），范围 −0.44…1.32 rad（−25.2°…75.6°）。

1600×900 下角色在屏幕上的高度（公式见附录 A）：

| 相机半径 | 可见高度 | 1.50 m 角色 | 头（0.333 m） | 眼（0.05 m） |
| --- | --- | --- | --- | --- |
| 82 m（默认） | 62.95 m | 约 21 px | 约 4.8 px | 约 0.7 px |
| 20 m | 15.35 m | 约 88 px | 约 19.5 px | 约 2.9 px |
| 9 m（最近） | 6.91 m | 约 195 px | 约 43 px | 约 6.5 px |
| 6.2 m（截图机位） | 4.76 m | 约 284 px | 约 63 px | 约 9.4 px |

结论：

- 默认 82 m 只能验收剪影、服装大色块、发型外轮廓；**不要用默认视角验收面部**。
- 面部验收用 r=9 m（头 43 px）或 r=6.2 m 截图机位（头 63 px）。
- 若要玩家近距离观察岛民，建议增加一个「聚焦岛民」相机预设（r≈6.2 m、elev≈0.35 rad），或在交互时临时拉近；室内需注意 near 0.3 与墙体遮挡，建议室内聚焦半径 3.5–4.5 m 并加简单相机避障（射线拉近）。

---

## 4. 本项目采用的设计原则（P1–P14 详解）

### P1 身高与头身比锁定

- 条款：岛民总高 1.50 m ±0.01（脚底 y=0，含发型最高点），头身比 4.2–5.0；头（含发）0.300–0.357 m；不改变现有世界尺度（门 1.14×1.94、室内净高 2.42、床约 1.9 m）。
- 依据：任务书 task-3；工程 HUMAN_HEIGHT=1.50、HUMAN_HEIGHT_TOL=0.010（游戏工程/scripts/isle_scale_spec.gd:25-26）；外部 2–3 头身不适合真人尺度世界（S1、S2、S3、S4）。
- 验收：headless 探针 AABB 高度 1.500±0.010；脚底 y=0；头顶 y=1.500±0.010。

### P2 面部可读性下限

- 条款：按 §1.3 的数值表建眼/眉/鼻/嘴/耳；五官在面部前平面；不做夸张卡通比例（不复制动森画风）。
- 依据：动森立绘量测（S2）与 Dinkum 5 类面部预设（S3）。
- 验收：r=9 m、1600×900 截图（头约 43 px）能分辨双眼、虹膜、嘴；r=82 m 截图面部不崩坏（不出现黑洞/穿插）。

### P3 发型剪影差异

- 条款：V4 至少 2 款（短发/中长发）；最宽处 ≥ 头宽 1.06 倍；顶部或侧向轮廓差 ≥0.03 m；只换 hair mesh，不动骨架。
- 依据：动森发型是最强识别变量（S1、S2）；Dinkum 可长期改发型（S3）。
- 验收：两款发型在 r=82 m 截图（角色约 21 px）仍可区分；切换后除 hair 外关节/AABB 度量差 ≤0.01 m。

### P4 极简离散外观

- 条款：V4 外观＝发型 2 款 × 共享发色 3–4 色 + 固定服装；无滑杆、无体型、无身高；名称确认后不改；预留镜台/衣柜修改接口，但不增加骨架变体。
- 依据：动森「所有特征不受起手样式限制 + 后期可随时改外观 + 身份信息锁定」（S1）；Dinkum 5 类离散选项 + Randomise + 沙龙/服装店长期修改（S3、S5）。
- 验收：创建/切换流程不需要重建骨架；枚举所有变体数量与材质数符合 P6。

### P5 外观与身体解耦

- 条款：唯一骨架、唯一关节长度、唯一身体半径（图净距 BODY_R=0.20；物理胶囊若做则 0.22–0.24）；换装只换 mesh/材质参数/挂点装饰；不改动画时长与相位。
- 依据：两作可调项清单（S1、S3）；工程 BODY_R（isle_villager_spots.gd:24）。
- 验收：两款发型切换前后，除 hair 节点外所有关节世界变换差 <1e-4 m；AABB 高差 ≤0.01 m。

### P6 draw call / 材质 / 三角面预算

场景预算（基线 V3.2 noon_clear：draw_calls 1838、tris 192066、mats 271，P7_V32_REPORT.md:293）：

| 方案 | 总 draw calls | vs V3.1 1804 | vs V3.2 1838 | 判定 |
| --- | --- | --- | --- | --- |
| 单角色 40 dc | 1878 | +4.1% | +2.2% | 通过（≤1894） |
| 单角色 60 dc（任务书 dc_est 上限） | 1898 | +5.2% | +3.3% | **超 V3.1+5% 口径 4 个 dc**；若按 V3.2+5%（≤1929）则通过 |
| 2 角色 ×40 dc | 1918 | +6.3% | +4.4% | 超 V3.1 口径；V3.2 口径内 |
| 3 角色 ×40 dc | 1958 | +8.5% | +6.5% | 超两种口径 |
| 4 角色 ×40 dc | 1998 | +10.8% | +8.7% | 超两种口径 |

- 条款：单角色目标 ≤40 dc；任务书硬指标 ≤60 dc_est 只能按 V3.2 基线口径使用；材质 ≤3/角色（皮肤/头发/服装），共享 toon 材质；总新增材质 ≤10（271→≤281）；tris ≤5000/角色；场景 tris 增量 ≤+3%（192066→≤197828）。
- 依据：P7_V32_REPORT.md:26、:293、:303、:321；V3.1/V3.2 的 ≤5% 容差口径。
- 风险与缓解：角色各关节的 MeshInstance3D 因动画无法静态合批（合批会锁死关节变换），dc 约等于网格件数；若 modeler 实测 60 dc，需把非动画附件（如口袋、扣件）合并到最近的关节网格，或把 NPC 数量限制为 1；服饰/鞋等静态附件可按材质合并，但每个关节的皮肤/服装仍各自独立。
- 验收：--perf（1600×900、quality=2、MSAA2）noon_clear 的 draw_calls、tris、mats、fps；fps 中位 ≥163.6（172.2×0.95）。

### P7 动画架构

- 条款：AnimationPlayer + 代码构造 Animation/AnimationLibrary；11 剪辑；不用 AnimationTree；不产生外部动画资产；不用常驻 Tween 做循环动作；blend 0.12–0.18 s（移动）/0.20–0.30 s（姿势）；speeds 用 speed_scale。
- 依据：S7、S8、S16、S17；AnimationTree 的接管 Note（S9）；任务书。
- 验收：探针列出 11 剪辑名称/时长/loop_mode；运行时 AnimationPlayer 在暂停时不前进；无 .anim/.tres 文件新增；切换时无 T-pose 帧（blend ≥0.12 s）。

### P8 运动方案

- 条款：图驱动运动学；walk 1.15 m/s；楼梯段 0.92 m/s（0.8 倍）；accel 6–8、decel 10 m/s²；转身 6–8 rad/s；保持直立；不引入 CharacterBody3D/碰撞体/navmesh。
- 依据：工程无碰撞体、步行图权威（isle_villager_spots.gd:3-24）；图已覆盖全部生活路线与座位/床。
- 验收：沿图从门廊到阁楼、从室内到花园/树下/秋千可完整行走；到点误差 ≤0.15 m；无悬空/穿模；座位/床的根 tween 结束位置误差 ≤0.02 m。

### P9 楼梯/斜坡

- 条款：stair 节点踏面顶 lerp；rise 0.16375、landing 1.860；门廊台阶节点 0/0.14/0.28/0.42 直接使用；不在楼梯上做重力/碰撞。
- 依据：cottage.gd:291-292、:326、:1335-1485；isle_villager_spots.gd:10-13。
- 验收：上下楼路径 y 连续、脚底贴地 ≤0.01 m、无瞬移；上楼速度约 0.92 m/s（0.8×walk）。

### P10 导航/寻路

- 条款：保留现有自写 A*（约 45 节点，含室内/楼梯/花园）；nearest_node 用水平 + |dy|*2；repath 仅在目标变更或卡住 >1 s；不烘焙 navmesh；不用 NavigationAgent3D。
- 依据：isle_villager_spots.gd:461、:504；NavigationAgent3D 需要导航数据且每帧驱动，avoidance 默认关且成本显著（S11、S12）；navmesh 默认参数与本项目不符，需重烘焙（S13、S14）。
- 升级触发：节点 >128、需要 partial path/权重/动态避障时，迁 AStar3D 或 navmesh（按 §3.5 参数）。
- 验收：任意两个生活节点之间路径可达；单次寻路 <0.5 ms（估算，探针可测）；无“原地抖动”式重复 repath。

### P11 步行与速度匹配

- 条款：walk 剪辑 0.96 s、v_ref=1.15 m/s、S_cycle=1.10 m；speed_scale=clamp(v/1.15, 0.85, 1.15)；idle↔walk blend 0.15 s；脚滑 ≤0.03 m/步；不做 root motion。
- 依据：S7、S8；附录 A 公式。
- 验收：在 1.15 m/s 与 0.92 m/s 两档速度下，脚底相对地面滑移 ≤0.03 m/步；walk 循环无相位跳变；idle↔walk 无脚部瞬移。

### P12 相机/可读性验收

- 条款：默认 82 m 只验剪影/配色（角色约 21 px）；r=9 m 验面部（头约 43 px）；elev 默认 16°、范围 −25.2°…75.6°；可选聚焦岛民预设 r≈6.2 m。
- 依据：游戏工程/scripts/main.gd:67-69、:1315-1328；附录 A 像素公式。
- 验收：两张截图（默认 82 m、近景 9 m）分别通过剪影/面部检查；近景不穿墙/不挡 UI。

### P13 暂停与时间同步

- 条款：暂停时 AnimationPlayer 与岛民移动同时停；恢复不跳变；循环动作不用常驻 Tween；若未来移动改 _physics_process，则 AnimationMixer.callback_mode_process 改为 PHYSICS。
- 依据：AnimationMixer.callback_mode_process 默认 IDLE（S8）；isle_cat.gd 的暂停经验（PROCESS_MODE_INHERIT + 时间累加器）。
- 验收：暂停 5 s 后继续，位置、动画帧、时间累加器均不跳变。

### P14 资产合规

- 条款：不复制外部资产/名称/文本/UI/角色设计；只使用设计原则；全部几何/材质程序化生成；配色用本项目色板；外部 URL 仅作设计依据。
- 依据：S1、S2、S3、S5。
- 验收：工程内无新增外部图片/模型/动画文件；角色 mesh 全部由 SurfaceTool/toon_material 生成。

---

## 5. 来源清单

### 5.1 已抓取来源（全部 2026-10-21，+08:00）

| 编号 | 标题/内容 | URL | 结果与用途 |
| --- | --- | --- | --- |
| S1 | How to Start a New Game (Animal Crossing: New Horizons)，任天堂官方支持 | https://en-americas-support.nintendo.com/app/answers/detail/a_id/49116/p/988 | HTTP 200；HTML 100000 字符截断，正文段完整提取；用于 §1.2–1.6 的外观/身份信息/比例原则 |
| S2 | Animal Crossing: New Horizons 官方商店页（8 张官方立绘） | https://www.nintendo.com/us/store/products/animal-crossing-new-horizons-switch/ | HTTP 200；取 dpr_2.0 立绘（char1 248×436、char4 236×413）做 alpha 轮廓量测；2.0 头身结论 |
| S3 | Character Customisation: How to express yourself on the Island（Dinkum Steam 公告，24 Jun 2022） | https://store.steampowered.com/news/posts/?appids=1062520&enddate=1656669915&feed=steam_community_announcements | HTTP 200；正文完整（46810 字符）；5 类外观 + Randomise + 沙龙/服装店 |
| S4 | Steam AppDetails：Dinkum（简介/截图） | https://store.steampowered.com/api/appdetails?appids=1062520&l=english | HTTP 200 JSON；15 张截图；用于 Dinkum 头身比目测与相机观察 |
| S5 | 3DM《Dinkum》改脸攻略（2022-09-05，EA 期） | https://www.3dmgame.com/gl/3859001.html | HTTP 200；正文完整；佐证 2022 EA 期「只能换头发，不能改脸」 |
| S6 | CharacterBody3D（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_characterbody3d.html | HTTP 200（RST 43397B）；默认参数与 move_and_slide/floor 判定行为 |
| S7 | AnimationPlayer（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_animationplayer.html | HTTP 200（RST 72722B）；play/seek/speed_scale/blend/process frame |
| S8 | AnimationMixer（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html | HTTP 200（RST 59010B）；AnimationLibrary 全局库、callback_mode_process、root motion、animation_finished |
| S9 | AnimationTree（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_animationtree.html | HTTP 200（RST 11816B）；「接管播放」Note 与 anim_player 属性 |
| S10 | AnimationTree 教程（Godot 4.7） | https://docs.godotengine.org/en/4.7/tutorials/animation/animation_tree.html | HTTP 200（RST 25220B）；root 节点类型、状态机过渡、Advance Condition/Expression 限制 |
| S11 | NavigationAgent3D（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_navigationagent3d.html | HTTP 200（RST 69744B）；每物理帧 get_next_path_position、avoidance 默认关且成本显著、desired distance 语义 |
| S12 | Using NavigationAgents（Godot 4.7 教程） | https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationagents.html | HTTP 200（RST 34855B）；agent 可选、导航系统不移动父节点、初始 map 未同步/频繁 repath 问题 |
| S13 | NavigationMesh（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_navigationmesh.html | HTTP 200（RST 42314B）；默认 agent_height 1.5、agent_max_climb 0.25、agent_radius 0.5、cell_size/cell_height 0.25 |
| S14 | Using navigation meshes（Godot 4.7 教程） | https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationmeshes.html | HTTP 200（RST 31545B）；cell 尺寸影响、agent_height/climb 剔除规则、过小 cell 可能卡死/崩溃 |
| S15 | AStar3D（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_astar3d.html | HTTP 200（RST 35772B）；add_point/connect_points/get_point_path、_compute_cost、weight_scale 语义 |
| S16 | Animation（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_animation.html | HTTP 200（RST 100000 字符截断，核心示例已取）；add_track/track_set_path/track_insert_key、length/loop_mode/step 默认值 |
| S17 | AnimationLibrary（Godot 4.7 类文档） | https://docs.godotengine.org/en/4.7/classes/class_animationlibrary.html | HTTP 200（RST 10209B）；add_animation/get/has/remove |

### 5.2 抓取失败/不可达来源（如实记录，不作为依据）

| URL | 结果 | 处理 |
| --- | --- | --- |
| https://docs.godotengine.org/en/4.x/classes/class_animationplayer.html | HTTP 404（/en/4.x/ 版本别名不存在） | 任务指定 URL；改用 https://docs.godotengine.org/en/4.7/classes/class_animationplayer.html（S7） |
| https://docs.godotengine.org/en/4.x/classes/class_characterbody3d.html | HTTP 404（同上） | 改用 https://docs.godotengine.org/en/4.7/classes/class_characterbody3d.html（S6） |
| https://nookipedia.com/wiki/Player | HTTP 503「Nookipedia is currently unavailable due to maintenance」 | 改用官方支持页（S1）与官方商店页（S2） |
| https://www.vg247.com/animal-crossing-new-horizons-character-customization-and-how-to-change-your-appearance | HTTP 200，但前 100000 字符均为内联 CSS，正文不可得 | 放弃，不作为依据 |
| https://www.vg247.com/animal-crossing-new-horizons-director-diversity | HTTP 200，同上（内联 CSS 占满） | 放弃 |
| https://animalcrossing.fandom.com/wiki/Player | fetch failed (TypeError) | 放弃 |
| https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=1062520&count=20 | 30 s 超时 | 改用 Steam 新闻页（S3）与 AppDetails（S4） |
| https://www.animal-crossing.com/new-horizons/ | 跨域重定向，无法取正文 | 放弃 |
| https://animalcrossing.nintendo.com | fetch failed | 放弃 |
| https://www.nintendo.co.jp/switch/acbaa/index.html | 跨域重定向到 nintendo.com | 放弃 |

### 5.3 项目内证据（只读观察，非外部来源）

| 文件:行 | 用途 |
| --- | --- |
| 游戏工程/scripts/isle_villager_spots.gd:3-24 | 步行图权威声明、node mode、spot kinds、BODY_R=0.20 |
| 游戏工程/scripts/isle_villager_spots.gd:26、:79、:131、:146、:156 | NODE_DEFS/EDGE_DEFS/SEAT_DEFS/VIEW_DEFS/BED |
| 游戏工程/scripts/isle_villager_spots.gd:220、:461、:504 | build()、自写 A*、nearest_node |
| 游戏工程/scripts/world.gd:189、:223、:270、:293、:297、:309 | _add_path、path_center_info、_h、surface_y、trail_clearance、_slope_ok |
| 游戏工程/scripts/isle_math.gd:40、:198、:452 | CAM_START_R=82、toon_material、hitbox |
| 游戏工程/scripts/cottage.gd:9、:106-107、:291-292、:326、:1335-1485 | 门洞 1.14×1.94、hitbox 用法、16 级楼梯 rise 0.16375、land_top 1.860、楼梯几何/stairs 数据 |
| 游戏工程/scripts/main.gd:42、:67-69、:667、:1315-1318、:1328 | _sim_seconds、elev/radius/fov、_process、缩放 9–240、elev 范围 |
| 游戏工程/scripts/isle_cat.gd | 程序化动画/暂停/调试范式 |
| 游戏工程/scripts/isle_scale_spec.gd:25-26；isle_scale_figure.gd:21 | HUMAN_HEIGHT=1.50、TOL=0.010 |
| 游戏工程/docs/P7_V32_REPORT.md:26、:293、:303、:321 | draw_calls 1838/1804、fps 172.2、tris 192066、mats 271、四轮一致 |
| 游戏工程/project.godot [input] | 只有 fly_* 动作，无步行/跳跃输入（V4 为 NPC） |

---

## 6. 未决问题与风险

1. **头身比冲突（已按任务书执行）**：外部参考为 2–3 头身，任务书要求 4.2–5 头身；本文按 4.2–5 写。若后续改为更接近动森的比例，需要同步放大世界尺度（门/家具/相机）并重跑尺度审计，成本高，不建议。
2. **动森比例来源是促销立绘**：1.9–2.1 头身为立绘量测，非实机模型；未取得实机正视图，结论仅用于「量级参考」。
3. **Dinkum 脸不可改的时效性**：S5 是 2022 EA 期资料（文章 2022-09-05），1.0 正式版是否开放改脸未核实；本项目按「创建后脸固定/发型可换」处理，风险低。
4. **角色 draw call 需实测**：本文预算按「dc≈网格件数」估算；任务书 dc_est ≤60 对应场景 1898，略超 V3.1+5% 的 1894 口径，需 Lead 确认口径（V3.1 基线 vs V3.2 基线）或把单角色压到 ≤56 dc。
5. **NPC 数量未定**：本报告按 1 个岛民（lone islander）估算；每增加 1 个 40 dc 角色总 dc +40（+2.2% vs V3.2）。若 Lead 计划多岛民，需要先定人数上限并做 LOD/合批方案。
6. **AnimationPlayer 轨道路径需与 modeler 对齐**：轨道 track_set_path 相对 AnimationMixer.root_node；需确认 root_node 指向模型根、关节节点命名稳定；联调前不要改关节层级。
7. **默认视角看不到脸**：82 m 下角色约 21 px；若要玩家观察岛民，建议新增聚焦相机预设（r≈6.2 m）或交互拉近；这是产品决策，需 Lead 确认。
8. **楼梯/门廊的物理备选方案未实测**：若未来引入 CharacterBody3D，隐形斜坡（32.2°/25.0°）与 snap 参数需 headless 探针实测验证。

---

## 附录 A 公式与推导

**头身比**：R = H_total / H_head；1.50/4.2 = 0.357 m，1.50/5.0 = 0.300 m。头宽按头高的 0.85–0.87 估算：0.26–0.30 m。

**屏幕像素高度**：px = H × viewport_h / (2 × r × tan(fov/2))；fov=42°、tan(21°)=0.383864、viewport_h=900：
- r=82：2×82×0.383864=62.95 m；1.5 m→21.4 px；
- r=20：15.35 m→87.9 px；
- r=9：6.91 m→195.4 px；头 0.333→43.4 px；眼 0.05→6.5 px；
- r=6.2：4.76 m→283.3 px；头→63.0 px；眼→9.4 px。

**步行匹配**：S_cycle = 2×step_length；f = v/S_cycle；T = 1/f；v_ref = S_cycle/T_clip；speed_scale = v/v_ref。
本项目：step_length=0.55 m → S_cycle=1.10 m；T_clip=0.96 s → v_ref=1.1458≈1.15 m/s；在 v=1.15 时 f=1.045 Hz（周期 0.956 s）；脚滑 = |v − speed_scale×v_ref|，目标 ≤0.03 m/步。

**楼梯坡角**：atan(rise_total/run_total)。A 段：atan(1.310/2.08)=32.2°；门廊：atan(0.42/0.90)=25.0°。均 < floor_max_angle 45°。

**预算**：V3.1 1804×1.05=1894.2；V3.2 1838×1.05=1929.9；fps 阈值 172.2×0.95=163.6；tris 阈值 192066×1.03=197828；材质 271→≤281。

## 附录 B 量测方法与限制

- 动森头身比：从任天堂官方商店页取 dpr_2.0 透明立绘，用 Pillow 12.3 读取 alpha 通道，计算每行不透明像素宽度/首末行，得到全身高与头+发区域边界；量测对象是促销立绘，不是实机模型，且不同角色/服装略有差异；结论只取量级（约 2 头身）。
- Dinkum 头身比：官方 Steam 截图（高角度俯视，纵向透视压缩）与商店 capsule 宣传画目测；无官方数值，仅作量级参考（约 2.5–3 头身）。
- 屏幕像素：按垂直 FOV 与 1600×900 视口解析计算，未考虑角色到相机距离与相机目标点偏移，实际会略有差异。
- 性能数字：直接引用工程 P7_V32_REPORT.md 的冻结口径（1600×900、quality=2、MSAA2、RTX2060），未在本次调研中重新实测。
- 本文未运行任何窗口模式长任务；未修改任何代码文件。

## 附录 C 环境与复现

- 引擎：D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe（Godot 4.7.2 stable，Forward+）。
- 工程：D:/休闲小岛幻境/游戏工程（分支 p7-v4-islander，HEAD 1b59e59）。
- headless 探针格式（供工程侧复现）：引擎 --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/xxx.gd。
- 抓取工具：DSH web_fetch（2026-10-21）；Godot 文档 RST 源：https://docs.godotengine.org/en/4.7/_sources/classes/class_xxx.rst.txt 与 https://docs.godotengine.org/en/4.7/_sources/tutorials/...rst.txt。
- 临时量测文件（不在 git 工程内，可删）：D:/休闲小岛幻境/research_tmp/（acnh_char1.png、acnh_char4.png、dinkum_ss0.jpg、dinkum_ss3.jpg、dinkum_capsule.jpg 等）。
