# P9 · P7-FINALIZE 料理玩法前置评估（PREP ONLY — 本阶段不实施料理系统）

- 项目：《休闲小岛幻境》 · 引擎：Godot 4.7.2 Stable / Forward+ · 主场景：res://isle.tscn
- 工程：D:/休闲小岛幻境/游戏工程 · 本阶段交付：D:/休闲小岛幻境/开发产物/P9/P7-finalize/
- 文档位置说明：项目工程文档统一放在 `游戏工程/docs/`（P8_* / OPEN_ISSUES 等），本文件按同一规范命名为 `docs/P9_P7F_COOKING_PREP.md`，同时在交付目录保留同名副本。
- 结论先行：当前工程已经具备“食材来源（五种作物产物 + 六种鱼）、共享库存原子事务、真实时间成长、世界存档、岛民活动/动画框架、HUD 面板体系”；**不具备**厨房/灶台家具、食谱数据、料理 UI、料理产物物品 ID。建议下一阶段以“1 个灶台交互点 + 3 道简单食谱 + 共享库存原子扣减/入账 + 存档兼容”为最小可行范围。

## 1. 规范物品 ID（直接复用，不新增食材 ID）

### 1.1 作物产物（5）
| 物品 ID | 显示名 | 来源 | 备注 |
|---|---|---|---|
| `wheat` | 小麦 | `scripts/isle_crops.gd` DEFS | 一次性收获，首收返 1 颗 seed_wheat |
| `corn` | 玉米 | 同上 | 再生 3 次（本阶段新规则），首收返种一次 |
| `watermelon` | 西瓜 | 同上 | 一次性 |
| `tomato` | 番茄 | 同上 | 再生 3 次 |
| `kale` | 羽衣甘蓝 | 同上 | 一次性，冬季可种 |

### 1.2 种子（5，料理不使用）
`seed_wheat` / `seed_corn` / `seed_watermelon` / `seed_tomato` / `seed_kale`。

### 1.3 近岸鱼（6）
| 物品 ID | 显示名 | 来源 |
|---|---|---|
| `fish_crucian` | 鲫鱼 | `scripts/isle_fish.gd` FISH_IDS |
| `fish_sardine` | 沙丁鱼 | 同上 |
| `fish_seabass` | 鲈鱼 | 同上 |
| `fish_puffer` | 河豚 | 同上 |
| `fish_salmon` | 鲑鱼 | 同上 |
| `fish_koi` | 彩鲤 | 同上 |

候选集 = `IsleInventory.catalog_ids()`：5 种子 → 5 产物 → 6 鱼（16 项）。料理产物需要新增 `dish_*` ID 并在烹饪阶段扩目录，属于该阶段工作，本阶段**不新增**。

## 2. 共享库存接口（料理必须复用，不建第二套库存）

`scripts/isle_inventory.gd`（唯一权威，RefCounted）：

| API | 语义 |
|---|---|
| `get_count(item_id) -> int` | 只读；未知 ID 返回 0 |
| `has_items(items: Dictionary) -> bool` | 批量检查，不修改 |
| `try_consume_items(items: Dictionary) -> bool` | **原子检查并扣除多种物品**；任一不足则整笔失败、库存不变（料理扣食材首选） |
| `remove_item(item_id, amount) -> bool` | 单物品原子扣除 |
| `add_items(items: Dictionary) -> bool` | 批量增加（原子，整笔合法才写入）；料理产物入账 |
| `item_snapshot() -> Dictionary` | 只读快照（HUD/探针） |
| `export_state()/restore_state()` | 存档一段（`version=1`, `{items}`）；由 `IsleSave` 调用 |

契约要点：
- 容量无限、同物品不限量堆叠；数量为非负整数；MAX_COUNT=1e9 仅防御脏数据。
- 未知 ID 写操作整笔失败；新增 `dish_*` 时必须先扩 `known_item_ids()/catalog_ids()` 与 `item_category()`，旧存档缺少新条目按 0 读取，**不需要**提升 STATE_VERSION。
- 料理事务建议顺序：`has_items(recipe.cost)` 预检 → `try_consume_items(cost)`（原子）→ `add_items({dish_id: 1})`；若入账失败（正常不会）按“食材已扣但产物未入账”的不可逆点处理——更稳的做法是扩 Inventory 一个 `craft(recipe)` 单事务 API（先校验、再一次性同时扣+加），这是推荐新增的唯一库存接口。

## 3. 当前时间/场景/交互基础

- 世界时间：`main._sim_seconds` 仍是天气/季节/日程/巡田的权威时钟；P7-FINALIZE 后**作物成长**改用现实时间（`IsleFarm.clock_mode="real"` + `advance_realtime`），与 `_sim_seconds` 解耦。料理若涉及“烹饪耗时”，建议用现实秒（与作物一致）或明确用哪条时钟，不能含糊。
- 作物/鱼来源已闭环：`IsleFarm` 播种/采收 → `IsleInventory.add_items`；钓鱼 `main` → `villager.commit_cb` → `inventory.add_items`；两者都必须保持单一库存。
- 岛民活动：`isle_villager.gd` 有 11 个状态（IDLE/WALK/SIT_IN/SIT/EAT/SIT_OUT/BED_IN/LIE_IN/SLEEP/LIE_OUT/BED_OUT）+ 巡田 + 钓鱼两套专用状态机；`isle_villager_spots.gd` 提供生活点/路径图；「料理」若做成岛民行为，应复用 `_act` 意图 + spot + 动画剪辑，不要新建平行调度。
- 场景家具：`isle_house_props.gd` 有 dining_table / chair / sofa / armchair / bed 等；**当前没有 stove / kitchen counter / 灶台/烤箱类节点**，也没有对应 spot。最小方案需要新增 1 个低多边形灶台（可复用现有 toon 材质与 box/cylinder 构件）并加 1 个烹饪 spot + 路径节点。
- 存档：`scripts/isle_save.gd` 保存 `IsleInventory.export_state()` + `IsleFarm.export_state()` + `saved_unix`，读档先完整校验再整体提交，离线时间按 unix 差值补涨（上限 1 天）。料理产物进共享库存后自动被现有存档覆盖；若料理有“灶台状态/进行中烹饪”，需要在该文件新增段并保持整份校验（建议首版不做进行中状态）。
- HUD：`hud.gd` 已有背包/时间/天气/钓鱼入口/面板样式（绘本低多边形风格，字体 simhei.ttf，CREAM/DIM/ACCENT 色）。料理 UI 应复用同一套面板/按钮工具函数，不新建 UI 框架。

## 4. 最小可行料理玩法（建议下一阶段首版）

1. **一道菜的定义**：`recipe_id` + 显示名 + `cost: Dictionary`（食材 ID→数量）+ `dish_id` + 产出数量（1）+ 可选料理动画时长。
2. **如何选择/制作**：玩家在灶台交互点按 HUD 按钮（与钓鱼按钮同级的“料理”入口）打开食谱面板；面板列出当前库存足够/不足的食谱（不足项灰显并显示缺料），点击“制作”执行单事务；不引入货币/售卖/等级。
3. **如何检查并一次性消耗**：`has_items` 预览 + `try_consume_items`（或新增 `craft()` 单事务）原子扣减；失败不产生任何变化、不进入 UI 假成功。
4. **失败不部分扣减**：使用库存原子 API；禁止“先扣 A 再检查 B”。探针要构造“第二种材料不足”“未知食材”“数量为 0”三类失败并断言库存逐项不变。
5. **产物入账**：`add_items({dish_id: 1})`；`dish_*` 在烹饪阶段加入 inventory 目录与背包分类（建议新增“料理”分类，显示顺序保持 作物→鱼→种子→料理 或按用户后续指定）。
6. **首版食谱数量**：建议 3 道（覆盖作物+鱼）——
   - `dish_veg_soup` 蔬菜汤：`kale×1 + tomato×1`（全素，早期可做）
   - `dish_grilled_fish` 烤鱼：`fish_crucian×1 + corn×1`（覆盖钓鱼+农田）
   - `dish_fruit_salad` 水果沙拉：`watermelon×1 + kale×1`（覆盖西瓜）
   （小麦可作为后续面食/储备食材，首版不必全用五种；食谱数值由产品/经济再定，但首版不要超过 3–4 道。）
7. **可复用能力**：IsleInventory 原子事务与目录、IsleSave 存档、HUD 面板/按钮工具、岛民活动/spot/动画框架、低多边形 toon 材质与程序化构件、钓鱼/背包/农田的“权威状态 → 视觉投影”分层。
8. **必须新增**：灶台家具节点 + 烹饪 spot + 路径节点（若岛民参与）、食谱数据表（纯数据脚本，无副作用）、料理交互入口与食谱面板、`dish_*` 物品 ID/目录/背包分类、料理动作动画（1 个循环 + 起锅退出即可；不需要复杂厨具链）、对应探针（原子性/库存/存档/UI/真实窗口）。
9. **继续推迟**：饥饿/饱食度/buff、食材品质/稀有度、食谱解锁/图鉴/任务、售卖/货币/经济、多级烹饪技能/失败概率、批量制作、食物腐败、复杂厨具（锅/烤箱状态机）。

## 5. 依赖与风险

- **必须先决定的产品规则**：a) 料理由玩家点击制作，还是岛民自主进行（建议玩家主导 + 岛民动画演出）；b) 是否要求靠近灶台（当前工程没有通用“靠近交互”系统，建议用灶台 spot + 距离判定，复用钓鱼的“岛民走到点”模式）；c) 烹饪耗时用现实秒还是 `_sim_seconds`（建议现实秒，与 P7-FINALIZE 农作一致）；d) 首版食谱是否固定 3 道、是否需要“已解锁”概念（建议固定 3 道、全部默认可用）。
- **回归风险**：料理 UI 与背包共享 HUD 左下角区域，需避免与时间/天气/背包/钓鱼面板互相遮挡；料理扣减必须复用共享库存，不能新增“料理用食材副本”；存档若新增段必须保持“整份校验、失败不改状态”的既有契约。
- **验证建议**：headless 单事务原子性（多组失败注入）、库存/背包显示一致、跨进程存档恢复、真实窗口 UI 与烹饪动画连续帧、与钓鱼/巡田/生活动作互斥（不抢占同一岛民状态机）。

## 6. 本阶段明确不做

- 不新增任何食材 ID、不新增 `dish_*`、不新增料理代码/场景节点/食谱文件/UI、不新增货币/售卖/等级/任务。
- 本文档只作为下一阶段的入口评估；具体实现范围需在下一阶段任务书中确认。

---

## 附：本阶段已具备的证据/基线引用

- 库存/背包：`scripts/isle_inventory.gd`、`scripts/hud.gd`（背包段），本阶段测试 `evidence/farm`、`evidence/settings`。
- 农田与真实时间：`scripts/isle_crops.gd`、`scripts/isle_farm.gd`、`scripts/isle_save.gd`，本阶段测试 `evidence/farm`、`evidence/save`。
- 钓鱼：`scripts/isle_fish.gd`、`scripts/isle_fishing_rig.gd`、`scripts/isle_villager.gd`（fishing 状态机），历史证据见 `开发产物/P9/P6/report.md` 与 `P6/visual-fix/report.md`。
- 岛民生活动作/日程：`scripts/isle_villager.gd`、`scripts/isle_villager_spots.gd`、`scripts/isle_villager_schedule.gd`，本阶段测试 `evidence/life`。