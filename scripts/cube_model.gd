class_name CubeModel
extends RefCounted

## 二阶魔方（Pocket Cube）逻辑模型。
## 只关心“状态”和“转动”，完全不涉及渲染，因此可以直接用于搜索求解。
##
## 状态表示：
##   8 个角块，每个角块用 code = 位置索引 * 3 + 朝向 表示（0..23）。
##   位置索引对应 POSITIONS 中的坐标（坐标分量只取 -1 / 1）。
##   朝向 0 表示该角块的“上/下贴纸”正好朝上或朝下（其余 1 / 2 为两种扭转）。
##
## 配色（西方标准配色）：
##   +X 红(R)  -X 橙(L)  +Y 黄(U)  -Y 白(D)  +Z 绿(F)  -Z 蓝(B)

# ----------------------------------------------------------------- 基本常量
const DIRS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const DIR_COLORS := [
	Color(0.85, 0.20, 0.18), # R 红
	Color(1.00, 0.53, 0.12), # L 橙
	Color(0.98, 0.82, 0.15), # U 黄
	Color(0.96, 0.96, 0.96), # D 白
	Color(0.20, 0.72, 0.32), # F 绿
	Color(0.16, 0.42, 0.88), # B 蓝
]
const DIR_NAMES := ["右", "左", "上", "下", "前", "后"]

# ----------------------------------------------------------------- 静态数据表
static var _tables_ready := false
static var POSITIONS: Array[Vector3i] = []      ## 位置索引 -> 坐标
static var POS_INDEX := {}                      ## 坐标 -> 位置索引
static var DIR_INDEX := {}                      ## 方向 -> 颜色索引
static var HOME: Array[Vector3i] = []           ## 角块 id -> 复原时的坐标
static var CODE_BASIS := []                     ## [id][code] -> Basis
static var MOVE_TABLE := []                     ## [move][id][code] -> code
static var MOVES := []                          ## 18 种转动（Dictionary）
static var NAME_TO_MOVE := {}                   ## "R" -> move 索引
static var INVERSE: Array[int] = []             ## 逆转动
static var MOVE_INDEX := {}                     ## "轴_层_转向" -> move 索引
static var U_MOVE := 0

# 实例状态
var codes := PackedByteArray()


func _init() -> void:
	reset()


# ================================================================= 初始化
static func ensure() -> void:
	if _tables_ready:
		return
	_tables_ready = true

	# 1. 8 个位置 + 方向索引
	POSITIONS = []
	POS_INDEX = {}
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				var p := Vector3i(x, y, z)
				POS_INDEX[p] = POSITIONS.size()
				POSITIONS.append(p)
	for i in DIRS.size():
		DIR_INDEX[DIRS[i]] = i
	HOME = POSITIONS.duplicate()

	# 2. 24 种旋转，建立 code -> Basis 的（双射）表
	var axes: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var rotations: Array[Basis] = []
	for xa: Vector3 in axes:
		for ya: Vector3 in axes:
			if absf(xa.dot(ya)) > 0.5:
				continue
			rotations.append(Basis(xa, ya, xa.cross(ya)))

	CODE_BASIS = []
	for id in HOME.size():
		var arr: Array[Basis] = []
		arr.resize(24)
		for b: Basis in rotations:
			var pos := to_vec3i(b * Vector3(HOME[id]))
			var code := int(POS_INDEX[pos]) * 3 + orientation_of(b, HOME[id])
			arr[code] = b
		CODE_BASIS.append(arr)

	# 3. 18 种转动
	MOVES = []
	NAME_TO_MOVE = {}
	var letters_pos := ["R", "U", "F"]
	var letters_neg := ["L", "D", "B"]
	for ai in 3:
		var axis_vec: Vector3 = axes[ai * 2]
		var axis_int := Vector3i(0, 0, 0)
		axis_int[ai] = 1
		for layer in [1, -1]:
			var letter: String = letters_pos[ai] if layer > 0 else letters_neg[ai]
			for q in [-1, 1, 2]:
				var rel: int = q * layer # 相对该面外法线的“顺时针”量
				var suffix := ""
				if rel == 1:
					suffix = "'"
				elif rel == 2:
					suffix = "2"
				var m := {
					"name": letter + suffix,
					"axis_index": ai,
					"axis_i": axis_int,
					"axis_vec": axis_vec,
					"layer": layer,
					"quarter": q,
					"basis": Basis(axis_vec, q * PI * 0.5),
				}
				NAME_TO_MOVE[letter + suffix] = MOVES.size()
				MOVES.append(m)

	# 4. 逆转动
	var key_to_mi := {}
	for mi in MOVES.size():
		var m: Dictionary = MOVES[mi]
		key_to_mi["%d_%d_%d" % [m["axis_index"], m["layer"], m["quarter"]]] = mi
	MOVE_INDEX = key_to_mi
	INVERSE.resize(MOVES.size())
	for mi in MOVES.size():
		var m: Dictionary = MOVES[mi]
		var q: int = m["quarter"]
		var iq: int = 2 if q == 2 else -q
		INVERSE[mi] = int(key_to_mi["%d_%d_%d" % [m["axis_index"], m["layer"], iq]])

	# 5. code -> code 转动表
	MOVE_TABLE = []
	for mi in MOVES.size():
		var m: Dictionary = MOVES[mi]
		var mb: Basis = m["basis"]
		var axis_i: Vector3i = m["axis_i"]
		var layer: int = m["layer"]
		var per_id := []
		for id in HOME.size():
			var row := PackedInt32Array()
			row.resize(24)
			for code in 24:
				var b: Basis = CODE_BASIS[id][code]
				var pos := to_vec3i(b * Vector3(HOME[id]))
				if axis_i.x * pos.x + axis_i.y * pos.y + axis_i.z * pos.z == layer:
					var nb: Basis = mb * b
					var npos := to_vec3i(nb * Vector3(HOME[id]))
					row[code] = int(POS_INDEX[npos]) * 3 + orientation_of(nb, HOME[id])
				else:
					row[code] = code
			per_id.append(row)
		MOVE_TABLE.append(per_id)

	# 6. 搜索用转动集合（只含 R/U/F 三个面，含逆与 180°，共 9 个）
	U_MOVE = int(NAME_TO_MOVE["U"])


static func to_vec3i(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))


## 朝向（标准约定）：绕该槽位的外法线把角块的“上/下贴纸”扭到上/下方向所需的 120° 次数
## 这样定义可以保证“所有角块朝向之和 ≡ 0 (mod 3)”这一标准不变量成立。
static func orientation_of(rot: Basis, home: Vector3i) -> int:
	var p := to_vec3i(rot * Vector3(home))       # 当前槽位
	var yd := Vector3(0, signi(p.y), 0)          # 槽位的上/下方向
	var s := rot * Vector3(0, signi(home.y), 0)  # 本角块“上/下贴纸”朝向
	if s.dot(yd) > 0.5:
		return 0
	var step := Basis(Vector3(p).normalized(), -TAU / 3.0)
	var d := yd
	for j in range(1, 3):
		d = step * d
		if s.dot(d) > 0.5:
			return j
	return 0


# ================================================================= 实例接口
func reset() -> void:
	ensure()
	codes = PackedByteArray()
	codes.resize(8)
	for id in 8:
		codes[id] = int(POS_INDEX[HOME[id]]) * 3


func set_from(other: PackedByteArray) -> void:
	codes = other.duplicate()


func clone_codes() -> PackedByteArray:
	return codes.duplicate()


# ================================================================= 纯函数工具
static func apply_move_to(state: PackedByteArray, mi: int) -> void:
	var tbl: Array = MOVE_TABLE[mi]
	for id in state.size():
		state[id] = tbl[id][state[id]]


static func apply_sequence(state: PackedByteArray, moves: Array) -> void:
	for mi in moves:
		apply_move_to(state, int(mi))


static func pos_of(code: int) -> Vector3i:
	return POSITIONS[code / 3]


static func ori_of(code: int) -> int:
	return code % 3


static func inverse_of(mi: int) -> int:
	return INVERSE[mi]


## 用（正半轴, 层符号, 转向）查找转动索引
static func find_move(axis_i: Vector3i, layer: int, quarter: int) -> int:
	ensure()
	var ai := 0
	if axis_i.y != 0:
		ai = 1
	elif axis_i.z != 0:
		ai = 2
	var key := "%d_%d_%d" % [ai, layer, quarter]
	return int(MOVE_INDEX.get(key, -1))


static func move_name(mi: int) -> String:
	return MOVES[mi]["name"]


static func sequence_to_string(moves: Array) -> String:
	var parts := PackedStringArray()
	for mi in moves:
		parts.append(move_name(int(mi)))
	return " ".join(parts)


static func parse_sequence(text: String) -> Array[int]:
	ensure()
	var out: Array[int] = []
	for tok in text.replace("\n", " ").replace(",", " ").split(" ", false):
		var t: String = tok.strip_edges()
		if t.is_empty():
			continue
		if NAME_TO_MOVE.has(t):
			out.append(int(NAME_TO_MOVE[t]))
	return out


static func invert_sequence(text: String) -> String:
	var moves := parse_sequence(text)
	var out := PackedStringArray()
	for i in range(moves.size() - 1, -1, -1):
		out.append(move_name(inverse_of(moves[i])))
	return " ".join(out)


# ================================================================= 目标判定
static func white_cubie_ids() -> Array[int]:
	ensure()
	var out: Array[int] = []
	for id in HOME.size():
		if HOME[id].y < 0:
			out.append(id)
	return out


static func top_cubie_ids() -> Array[int]:
	ensure()
	var out: Array[int] = []
	for id in HOME.size():
		if HOME[id].y > 0:
			out.append(id)
	return out


## 前 k 个白色角块是否已经归位（位置正确 + 朝向正确）
static func prefix_ok(state: PackedByteArray, k: int) -> bool:
	ensure()
	var ids := white_cubie_ids()
	var n: int = mini(k, ids.size())
	for i in n:
		var id: int = ids[i]
		if int(state[id]) != int(POS_INDEX[HOME[id]]) * 3:
			return false
	return true


static func first_layer_solved(state: PackedByteArray) -> bool:
	return prefix_ok(state, 4)


static func first_layer_count(state: PackedByteArray) -> int:
	ensure()
	var ids := white_cubie_ids()
	var n := 0
	for id: int in ids:
		if int(state[id]) == int(POS_INDEX[HOME[id]]) * 3:
			n += 1
	return n


static func top_oriented(state: PackedByteArray) -> bool:
	ensure()
	for id in HOME.size():
		if HOME[id].y > 0 and (int(state[id]) % 3) != 0:
			return false
	return true


static func top_oriented_count(state: PackedByteArray) -> int:
	ensure()
	var n := 0
	for id in HOME.size():
		if HOME[id].y > 0 and (int(state[id]) % 3) == 0:
			n += 1
	return n


static func is_solved(state: PackedByteArray) -> bool:
	ensure()
	for id in HOME.size():
		if int(state[id]) != int(POS_INDEX[HOME[id]]) * 3:
			return false
	return true


# ================================================================= 渲染辅助
## 位置索引 -> 角块 id
static func pos_to_cubie(state: PackedByteArray) -> Array[int]:
	ensure()
	var out: Array[int] = []
	out.resize(8)
	for id in state.size():
		out[int(state[id]) / 3] = id
	return out


## 角块 id 在 world_dir 方向上的贴纸颜色
static func sticker_color(state: PackedByteArray, id: int, world_dir: Vector3i) -> Color:
	ensure()
	var b: Basis = CODE_BASIS[id][state[id]]
	var local := to_vec3i(b.inverse() * Vector3(world_dir))
	var idx: int = DIR_INDEX.get(local, 0)
	return DIR_COLORS[idx]


## 随机打乱序列
static func random_scramble(length: int = 12) -> Array[int]:
	ensure()
	var out: Array[int] = []
	var last_axis := -1
	while out.size() < length:
		var mi: int = randi() % MOVES.size()
		var ax: int = MOVES[mi]["axis_index"]
		if ax == last_axis:
			continue
		last_axis = ax
		out.append(mi)
	return out
