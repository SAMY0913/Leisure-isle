class_name IsleBatch
extends RefCounted
## P7-V3.1 静态合批工具（降低 draw call，不改变观感）
##
## 背景
## ------------------------------------------------------------------
## P7-V3 在家具库 / 楼梯 / 门廊等处新增了大量"一个部件一个 MeshInstance3D"的
## 程序化网格（每个部件 = 1 mesh instance × 1 surface × 2 pass(toon + outline)）。
## Forward+ 不做自动静态合批，因此 draw call 与 objects 随部件数线性增长。
##
## 做法
## ------------------------------------------------------------------
## 把某个 Node3D 子树里 **静态、同材质、同顶点属性** 的 surface 合并成少量
## "多 surface ArrayMesh"（每 surface 一个材质，走 surface material 而不是
## material_override —— 后者会覆盖全部 surface）。
## * 顶点/法线/切线/UV 的局部→组局部坐标变换由引擎完成（SurfaceTool.append_from），
##   三角形、法线方向与着色结果不变；
## * 材质对象原样复用（不 copy），toon 材质上的 next_pass 描边通道、self_lit、
##   glow 等参数全部保留；
## * outline.gdshader 沿 NORMAL 在 **模型空间** 外扩固定宽度；合并前后每个顶点的
##   法线与其所属 group 的局部尺度都不变，因此描边粗细与接缝表现不变。
##
## 安全边界（宁可少合并，也不改变行为）
## ------------------------------------------------------------------
## * 只合并 shader 为 shaders/toon.gdshader 的 ShaderMaterial —— 玻璃(glass)、
##   草地(grass)、加色光晕/影子斑(additive/alpha StandardMaterial)、海面、天空
##   一律跳过（半透明排序与 billboard 依赖独立实例）。
## * **一个 MeshInstance3D 只有在它的全部 surface 都可合并时才参与**，避免
##   "合并一半 + 原实例残留"造成的重复绘制或几何丢失。
## * 跳过带 `no_batch` meta 的子树（动态件用这个契约标记）、有脚本的节点、
##   MultiMeshInstance3D、GPUParticles3D、CPUParticles3D、Glow/Halo/Blob/Batch_ 前缀。
## * 跳过调用方显式排除的子树。
## * 合并键 =(split 区域, 材质实例, 顶点属性签名)；落盘再按 (cast_shadow, layers)
##   分出独立 MeshInstance3D —— 不同键绝不混进同一 surface，不同区域绝不混进
##   同一个实例，因此不会出现"整栋房屋只能整体显隐"。
##
## 用法
## ------------------------------------------------------------------
##   IsleBatch.merge_static(prop_node)                        # 单件家具
##   IsleBatch.merge_static(stairs_node)                       # 楼梯整段
##   IsleBatch.merge_static(root, {"split": cb, "skip": [p]})   # 按区域分组

const SKIP_PREFIX := ["Glow", "Halo", "Blob", "Batch_"]
const TOON_SHADER_PATH := "res://shaders/toon.gdshader"

## 把 group 子树中的静态 MeshInstance3D 合并为按材质的少量 mesh。
## opts:
##   skip: Array[Node]   需要整体跳过的子树（动态件）
##   split: Callable     接收 MeshInstance3D，返回区域名（默认全归 "")
##   dry_run: bool       只统计不落地（分析用）
##   min_instances: int  候选实例少于该数量则直接返回（默认 2）
## 返回 {"ok", "instances", "surfaces_in", "surfaces_out", "groups",
##       "tris_in", "tris_out", "merged"}
static func merge_static(group: Node3D, opts: Dictionary = {}) -> Dictionary:
	var res := {
		"ok": false, "instances": 0, "surfaces_in": 0, "surfaces_out": 0,
		"groups": 0, "tris_in": 0, "tris_out": 0, "merged": false,
	}
	if group == null or not is_instance_valid(group):
		return res
	var skip: Array = opts.get("skip", [])
	var split_cb: Callable = opts.get("split", Callable())
	var dry: bool = bool(opts.get("dry_run", false))
	var min_inst: int = int(opts.get("min_instances", 2))

	# ---- 1) 收集候选（整实例可合并才收录）----
	var raw: Array = []
	_collect(group, skip, raw)
	var cands: Array = []
	var surfaces_in := 0
	var tris_in := 0
	for mi in raw:
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null or mesh.get_surface_count() <= 0:
			continue
		var all_ok := true
		for s in range(mesh.get_surface_count()):
			if not _mat_allows(_surface_material(mi, mesh, s)):
				all_ok = false
				break
		if not all_ok:
			continue
		cands.append(mi)
		surfaces_in += mesh.get_surface_count()
		tris_in += _tri_count(mesh)
	res["instances"] = cands.size()
	res["surfaces_in"] = surfaces_in
	res["tris_in"] = tris_in
	if cands.size() < min_inst:
		res["ok"] = true
		return res

	# ---- 2) 按 (区域, 材质, 顶点属性签名) 建 SurfaceTool ----
	var buckets: Dictionary = {}
	var order: Array = []
	for mi in cands:
		var node: MeshInstance3D = mi
		var mesh: Mesh = node.mesh
		var xf: Transform3D = _rel_xf(group, node)
		var spl: String = String(split_cb.call(node)) if split_cb.is_valid() else ""
		for s in range(mesh.get_surface_count()):
			var mat: Material = _surface_material(node, mesh, s)
			var key: String = "%s||%d||%s" % [spl, mat.get_instance_id(), _fmt_key(mesh, s)]
			if not buckets.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				buckets[key] = {
					"st": st, "mat": mat, "split": spl, "n": 0,
					"shadow": node.cast_shadow, "layers": node.layers,
				}
				order.append(key)
			var b: Dictionary = buckets[key]
			(b["st"] as SurfaceTool).append_from(mesh, s, xf)
			b["n"] = int(b["n"]) + 1

	res["groups"] = order.size()
	res["surfaces_out"] = order.size()
	# 收益判定：合并后 surface 数必须严格少于合并前，否则不动结构
	if order.is_empty() or order.size() >= surfaces_in:
		res["ok"] = true
		return res
	if dry:
		res["ok"] = true
		res["merged"] = true
		return res

	# ---- 3) 按 (区域, cast_shadow, layers) 组装多 surface ArrayMesh ----
	var out_map: Dictionary = {}
	var out_order: Array = []
	for k in order:
		var b: Dictionary = buckets[k]
		var arrays: Array = (b["st"] as SurfaceTool).commit_to_arrays()
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var gk := "%s||%d||%d" % [String(b["split"]), int(b["shadow"]), int(b["layers"])]
		if not out_map.has(gk):
			out_map[gk] = {
				"mesh": ArrayMesh.new(), "split": String(b["split"]),
				"shadow": int(b["shadow"]), "layers": int(b["layers"]), "n": 0,
			}
			out_order.append(gk)
		var om: Dictionary = out_map[gk]
		var am: ArrayMesh = om["mesh"]
		var sidx: int = am.get_surface_count()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(sidx, b["mat"])
		om["n"] = int(om["n"]) + 1

	if out_order.is_empty():
		res["ok"] = true
		return res

	# ---- 4) 替换：先记录部件溯源清单，再加新节点、删旧实例 ----
	# 合批后独立的 MeshInstance3D 节点会消失，但"建过哪些部件、各自多大、在什么位置"
	# 是验收需要的能力（探针要断言踏步级数、井壁面数、拱券尺寸……）。这里把被合并
	# 部件的几何契约写进 group 的 batch_manifest meta，供探针按部件级粒度复核。
	# 清单只记录构建期信息，不参与渲染，也不增加帧开销。
	var manifest: Array = []
	if group.has_meta("batch_manifest"):
		var prev: Variant = group.get_meta("batch_manifest")
		if prev is Array:
			manifest = prev
	for mi in cands:
		var node: MeshInstance3D = mi
		var m: Mesh = node.mesh
		manifest.append({
			"name": String(node.name),
			"kind": _mesh_kind(m),
			"size": _mesh_size(m),
			# 原节点自身的局部变换（相对它原来的直接父节点）——探针按
			# "位置/旋转/尺寸"复核部件时用的就是这一口径，合批前后语义不变。
			"xf": node.transform,
			# 相对合批根节点的变换，供按空间区域做二次查询（可选）。
			"xf_group": _rel_xf(group, node),
			"parent": String(node.get_parent().name) if node.get_parent() != null else "",
			"tris": _tri_count(m),
			"mat": _mat_key(_surface_material(node, m, 0)),
		})
	group.set_meta("batch_manifest", manifest)

	var created: int = 0
	for gk in out_order:
		var om: Dictionary = out_map[gk]
		var nmi := MeshInstance3D.new()
		nmi.name = "Batch_%02d" % created
		nmi.mesh = om["mesh"]
		nmi.cast_shadow = om["shadow"]
		nmi.layers = om["layers"]
		nmi.set_meta("batch_surfaces", int(om["n"]))
		nmi.set_meta("batch_split", String(om["split"]))
		group.add_child(nmi)
		created += 1
	var removed := 0
	for mi in cands:
		if not is_instance_valid(mi):
			continue
		var parent := (mi as Node).get_parent()
		if parent != null:
			parent.remove_child(mi)
		(mi as Node).free()
		removed += 1

	var tris_out := 0
	var surf_out := 0
	for gk in out_order:
		var am2: ArrayMesh = out_map[gk]["mesh"]
		tris_out += _tri_count(am2)
		surf_out += am2.get_surface_count()
	res["merged"] = true
	res["instances"] = removed
	res["tris_out"] = tris_out
	res["surfaces_out"] = surf_out
	res["ok"] = true
	return res

# ------------------------------------------------------------------
# 内部
# ------------------------------------------------------------------

static func _collect(n: Node, skip: Array, out: Array) -> void:
	for c in n.get_children():
		if skip.has(c):
			continue
		if c is MultiMeshInstance3D or c is GPUParticles3D or c is CPUParticles3D:
			continue
		if c.has_meta("no_batch") and bool(c.get_meta("no_batch")):
			continue
		if c.get_script() != null:
			continue
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			if mi.mesh == null:
				continue
			if _name_skipped(String(mi.name)):
				continue
			out.append(mi)
			continue
		_collect(c, skip, out)

static func _name_skipped(nm: String) -> bool:
	for p in SKIP_PREFIX:
		if nm.begins_with(String(p)):
			return true
	return false

## 部件溯源清单用的网格分类与关键尺寸（与 BoxMesh/CylinderMesh/... 的属性一一对应，
## 让探针在合批后仍能按"什么形状、多大"复核部件）。
static func _mesh_kind(m: Mesh) -> String:
	if m is BoxMesh:
		return "Box"
	if m is CylinderMesh:
		return "Cyl"
	if m is SphereMesh:
		return "Sphere"
	if m is QuadMesh:
		return "Quad"
	if m is PrismMesh:
		return "Prism"
	return "Other"

static func _mesh_size(m: Mesh) -> Vector3:
	if m is BoxMesh:
		return (m as BoxMesh).size
	if m is CylinderMesh:
		var c := m as CylinderMesh
		return Vector3(c.top_radius, c.height, c.bottom_radius)
	if m is SphereMesh:
		var s := m as SphereMesh
		return Vector3(s.radius, s.height, s.radius)
	if m is QuadMesh:
		var q := m as QuadMesh
		return Vector3(q.size.x, q.size.y, 0.0)
	if m is PrismMesh:
		var p := m as PrismMesh
		return Vector3(p.size.x, p.size.y, p.size.z)
	return Vector3.ZERO

## 材质标识：toon 材质的关键外观参数（albedo + 描边宽度），供探针断言"合并后
## 外观材质没有被替换/丢失"。
static func _mat_key(mat: Material) -> String:
	if not (mat is ShaderMaterial):
		return ""
	var sm := mat as ShaderMaterial
	var alb: Variant = sm.get_shader_parameter("albedo")
	var ow := "none"
	if sm.next_pass is ShaderMaterial:
		ow = str((sm.next_pass as ShaderMaterial).get_shader_parameter("outline_width"))
	return "%s|%s" % [str(alb), ow]

static func _surface_material(mi: MeshInstance3D, mesh: Mesh, s: int) -> Material:
	var m: Material = mi.material_override
	if m == null:
		m = mesh.surface_get_material(s)
	return m

## 顶点属性签名：SurfaceTool.append_from 要求同组 surface 的属性集完全一致。
## Mesh 基类没有 surface_get_format()（只有 ArrayMesh 有），因此用 arrays 里各属性
## 的存在性推导签名。PrimitiveMesh（Box/Cylinder/Sphere/Quad）一律走同一条快路径，
## 手工 ArrayMesh（SurfaceTool.commit 出来的）逐 surface 检查。
static func _fmt_key(mesh: Mesh, s: int) -> String:
	if not (mesh is ArrayMesh):
		return "prim"
	var arr := mesh.surface_get_arrays(s)
	var mask := 0
	if arr.size() > Mesh.ARRAY_NORMAL and arr[Mesh.ARRAY_NORMAL] != null:
		mask |= 1
	if arr.size() > Mesh.ARRAY_TANGENT and arr[Mesh.ARRAY_TANGENT] != null:
		mask |= 2
	if arr.size() > Mesh.ARRAY_TEX_UV and arr[Mesh.ARRAY_TEX_UV] != null:
		mask |= 4
	if arr.size() > Mesh.ARRAY_COLOR and arr[Mesh.ARRAY_COLOR] != null:
		mask |= 8
	if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
		mask |= 16
	return "am%d" % mask

## 只允许 toon 材质参与合批：它是本工程唯一"不透明、无 billboard、无透明混合"的
## 通用表面材质；玻璃/草/水/天/加色光晕各有独立 shader，排序与渲染行为不同。
static func _mat_allows(mat: Material) -> bool:
	if mat == null:
		return false
	if not (mat is ShaderMaterial):
		return false
	var sh: Shader = (mat as ShaderMaterial).shader
	if sh == null:
		return false
	var path := sh.resource_path
	if path == "":
		return false
	return path.ends_with(TOON_SHADER_PATH)

static func _rel_xf(group: Node3D, n: Node3D) -> Transform3D:
	if group.is_inside_tree() and n.is_inside_tree():
		return group.global_transform.affine_inverse() * n.global_transform
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != group:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

static func _tri_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var t := 0
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var vc: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var ic: int = 0
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			ic = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		t += ic / 3 if ic > 0 else vc / 3
	return t
