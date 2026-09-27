class_name CubeSolver
extends RefCounted

## 二阶魔方求解器（面向教学：按“层先法”三阶段求解）
##   阶段 0：复原白色一层   —— IDA*（查表启发式，毫秒级）
##   阶段 1：顶层朝向 OLL   —— 标准公式 + AUF 匹配，失败时回退 IDA*
##   阶段 2：顶层归位 PLL   —— 标准公式 + AUF 匹配，失败时回退 IDA*
##
## 启发式表（启动时一次性建好，使用与搜索相同的 R/U/F 转动集合）：
##   _dist_home_oriented 单个角块 归位(位置+朝向) 的最少步数
##   _dist_ori_up        单个上层角块 朝向正确     的最少步数
##   _dist_pos[k]        前 k 个白色角块 位置正确  的最少步数（8^k 状态 BFS）

const PHASE_DONE := 3

const KIND_PREFIX := 0        # 前 k 个白色角块归位
const KIND_LAYER_TOP := 1     # 白色一层归位 且 顶层朝向正确
const KIND_SOLVED := 2        # 完全复原

# 顶层朝向（OLL）常用公式
const OLL_ALGS := [
	{"name": "小鱼（Sune）", "moves": "R U R' U R U2 R'"},
	{"name": "逆小鱼（Anti-Sune）", "moves": "R U2 R' U' R U' R'"},
	{"name": "H 型（双小鱼）", "moves": "R U R' U R U' R' U R U2 R'"},
	{"name": "Π 型（Pi）", "moves": "R U2 R2 U' R2 U' R2 U2 R"},
	{"name": "T 型", "moves": "R U R' U' R' F R F'"},
	{"name": "L 型", "moves": "F R' F' R U R U' R'"},
]

# 顶层归位（PLL）公式
const PLL_ALGS := [
	{"name": "相邻两角互换（T 型）", "moves": "R U R' U' R' F R2 U' R' U' R U R' F'"},
	{"name": "对角两角互换（Y 型）", "moves": "F R U' R' U' R U R' F' R U R' U' R' F R F'"},
]

static var _ready := false
static var _search_moves: Array[int] = []  ## 搜索与建表统一使用全部 18 种转动
static var _search_axes: Array[int] = []
static var _nodes_left := 0
static var _pow8 := [1, 8, 64, 512, 4096]
static var _white_ids: Array[int] = []
static var _top_ids: Array[int] = []
static var _home_code := PackedInt32Array()

static var _dist_home_oriented := []   # [0] 下层角块表, [1] 上层角块表
static var _dist_white := PackedInt32Array()
static var _dist_ori_up := PackedInt32Array()
static var _dist_pos := []             # [k-1] -> PackedInt32Array
static var _seen := {}                 # 置换表：子状态 -> 已访问的最小 g

# 白色一层精确距离表（BFS 预计算，4 个白色角块 (位置+朝向) -> 步数）
# 构建采用“分帧推进”，不会卡住主线程；solve_first_layer 会在需要时同步补完。
static var _fl_dist := PackedInt32Array()
static var _fl_ready := false
static var _fl_started := false
static var _fl_queue := PackedInt32Array()
static var _fl_head := 0


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	CubeModel.ensure()
	for mi in CubeModel.MOVES.size():
		_search_moves.append(int(mi))
		_search_axes.append(int(CubeModel.MOVES[mi]["axis_index"]))
	_home_code.resize(8)
	for id in 8:
		_home_code[id] = int(CubeModel.POS_INDEX[CubeModel.HOME[id]]) * 3
	_white_ids = CubeModel.white_cubie_ids()
	_top_ids = CubeModel.top_cubie_ids()
	_build_tables()


# ================================================================= 子状态编号（置换表）
static func _sub_key(state: PackedByteArray, kind: int, k: int) -> int:
	if kind == KIND_PREFIX:
		var n: int = mini(k, 4)
		var key := 0
		for i in n:
			key = key * 24 + int(state[_white_ids[i]])
		return key
	return _state_key(state)


static func _state_key(state: PackedByteArray) -> int:
	var key := 0
	for id in 8:
		key = key * 24 + int(state[id])
	return key


# ================================================================= 启发式表
## 单个角块从 goal_codes 出发的最短步数（图无向，正向 BFS 覆盖整个连通分量）
static func _bfs_codes(goal_codes: Array, id_ref: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(24)
	dist.fill(-1)
	var queue: Array[int] = []
	for c: int in goal_codes:
		if dist[c] < 0:
			dist[c] = 0
			queue.append(c)
	var head := 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		var nd: int = dist[c] + 1
		for mi: int in _search_moves:
			var nc: int = CubeModel.MOVE_TABLE[mi][id_ref][c]
			if dist[nc] < 0:
				dist[nc] = nd
				queue.append(nc)
	return dist


## 前 k 个白色角块“位置正确”的最短步数表，key = sum(pos_i * 8^i)
static func _build_pos_table(k: int) -> PackedInt32Array:
	var size: int = _pow8[k]
	var dist := PackedInt32Array()
	dist.resize(size)
	dist.fill(-1)
	var goal := 0
	for i in k:
		goal += (_home_code[_white_ids[i]] / 3) * _pow8[i]
	dist[goal] = 0
	var queue: Array[int] = [goal]
	var head := 0
	while head < queue.size():
		var key: int = queue[head]
		head += 1
		var nd: int = dist[key] + 1
		for mi: int in _search_moves:
			var nk := 0
			for i in k:
				var p: int = (key / _pow8[i]) % 8
				var np: int = int(CubeModel.MOVE_TABLE[mi][_white_ids[i]][p * 3]) / 3
				nk += np * _pow8[i]
			if dist[nk] < 0:
				dist[nk] = nd
				queue.append(nk)
	return dist


static func _build_tables() -> void:
	_dist_home_oriented = []
	_dist_home_oriented.append(_bfs_codes([_home_code[_white_ids[0]]], _white_ids[0]))
	_dist_home_oriented.append(_bfs_codes([_home_code[_top_ids[0]]], _top_ids[0]))
	_dist_white = _dist_home_oriented[0]

	var ori_goals: Array[int] = []
	for p in 8:
		ori_goals.append(p * 3)
	_dist_ori_up = _bfs_codes(ori_goals, _top_ids[0])

	_dist_pos = []
	for k in range(1, 5):
		_dist_pos.append(_build_pos_table(k))


# ================================================================= 启发函数
static func _pos_key(state: PackedByteArray, k: int) -> int:
	var key := 0
	for i in k:
		key += (int(state[_white_ids[i]]) / 3) * _pow8[i]
	return key


static func _h_prefix(state: PackedByteArray, k: int) -> int:
	var n: int = mini(k, 4)
	var h: int = _dist_pos[n - 1][_pos_key(state, n)]
	for i in n:
		h = maxi(h, _dist_white[int(state[_white_ids[i]])])
	return h


static func _h_top_ori(state: PackedByteArray) -> int:
	var h := 0
	for id: int in _top_ids:
		h = maxi(h, _dist_ori_up[int(state[id])])
	return h


static func _h_all(state: PackedByteArray) -> int:
	var h := _h_prefix(state, 4)
	h = maxi(h, _h_top_ori(state))
	for id in 8:
		var t: int = 0 if CubeModel.HOME[id].y < 0 else 1
		h = maxi(h, _dist_home_oriented[t][int(state[id])])
	return h


static func _heuristic(state: PackedByteArray, kind: int, k: int) -> int:
	match kind:
		KIND_PREFIX:
			return _h_prefix(state, k)
		KIND_LAYER_TOP:
			return maxi(_h_prefix(state, 4), _h_top_ori(state))
		_:
			return _h_all(state)


# ================================================================= 目标判定
static func _goal(state: PackedByteArray, kind: int, k: int) -> bool:
	match kind:
		KIND_PREFIX:
			var n: int = mini(k, 4)
			for i in n:
				var id: int = _white_ids[i]
				if int(state[id]) != _home_code[id]:
					return false
			return true
		KIND_LAYER_TOP:
			for id: int in _white_ids:
				if int(state[id]) != _home_code[id]:
					return false
			for id: int in _top_ids:
				if int(state[id]) % 3 != 0:
					return false
			return true
		_:
			for id in 8:
				if int(state[id]) != _home_code[id]:
					return false
			return true


# ================================================================= IDA*
static func search(
	state: PackedByteArray,
	kind: int,
	max_depth: int,
	k: int = 4,
	node_budget: int = 600000
) -> Array[int]:
	_ensure()
	var work := state.duplicate()
	var path: Array[int] = []
	_nodes_left = node_budget
	var start_h := _heuristic(work, kind, k)
	for limit in range(maxi(start_h, 0), max_depth + 1):
		path.clear()
		_seen.clear()
		if _dfs(work, kind, k, 0, limit, -1, path):
			return path.duplicate()
		if _nodes_left <= 0:
			break
	return []


static func _dfs(
	work: PackedByteArray,
	kind: int,
	k: int,
	g: int,
	limit: int,
	last_axis: int,
	path: Array[int]
) -> bool:
	_nodes_left -= 1
	if _nodes_left <= 0:
		return false
	if _goal(work, kind, k):
		return true
	if g + _heuristic(work, kind, k) > limit:
		return false
	var skey := _sub_key(work, kind, k)
	if _seen.has(skey):
		if int(_seen[skey]) <= g:
			return false
	_seen[skey] = g
	for i in _search_moves.size():
		var ax: int = _search_axes[i]
		if ax == last_axis:
			continue
		var mi: int = _search_moves[i]
		CubeModel.apply_move_to(work, mi)
		path.append(mi)
		if _dfs(work, kind, k, g + 1, limit, ax, path):
			return true
		path.pop_back()
		CubeModel.apply_move_to(work, CubeModel.INVERSE[mi])
		if _nodes_left <= 0:
			return false
	return false


# ================================================================= 白色一层精确距离表
static func start_first_layer_build() -> void:
	_ensure()
	if _fl_started or _fl_ready:
		return
	_fl_started = true
	_fl_dist = PackedInt32Array()
	_fl_dist.resize(331776)
	_fl_dist.fill(-1)
	var w0: int = _white_ids[0]
	var w1: int = _white_ids[1]
	var w2: int = _white_ids[2]
	var w3: int = _white_ids[3]
	var goal: int = _home_code[w0] + _home_code[w1] * 24 + _home_code[w2] * 576 + _home_code[w3] * 13824
	_fl_dist[goal] = 0
	_fl_queue = PackedInt32Array()
	_fl_queue.append(goal)
	_fl_head = 0


## 推进一步（带时间预算），返回是否已经完成
static func first_layer_build_step(budget_ms: float = 8.0) -> bool:
	if _fl_ready:
		return true
	if not _fl_started:
		start_first_layer_build()
	var w0: int = _white_ids[0]
	var w1: int = _white_ids[1]
	var w2: int = _white_ids[2]
	var w3: int = _white_ids[3]
	var mv: Array = CubeModel.MOVE_TABLE
	var t0 := Time.get_ticks_msec()
	while _fl_head < _fl_queue.size():
		var key: int = _fl_queue[_fl_head]
		_fl_head += 1
		var c0: int = key % 24
		var c1: int = (key / 24) % 24
		var c2: int = (key / 576) % 24
		var c3: int = (key / 13824) % 24
		var nd: int = _fl_dist[key] + 1
		for mi in _search_moves:
			var tbl: Array = mv[mi]
			var t0b: PackedInt32Array = tbl[w0]
			var t1b: PackedInt32Array = tbl[w1]
			var t2b: PackedInt32Array = tbl[w2]
			var t3b: PackedInt32Array = tbl[w3]
			var nk: int = t0b[c0] + t1b[c1] * 24 + t2b[c2] * 576 + t3b[c3] * 13824
			if _fl_dist[nk] < 0:
				_fl_dist[nk] = nd
				_fl_queue.append(nk)
		if Time.get_ticks_msec() - t0 > budget_ms:
			break
	if _fl_head >= _fl_queue.size():
		_fl_ready = true
		_fl_queue = PackedInt32Array()
		return true
	return false


## 同步等待表构建完成（求解时调用）
static func ensure_first_layer_table() -> void:
	start_first_layer_build()
	while not _fl_ready:
		first_layer_build_step(250.0)


static func _fl_key(state: PackedByteArray) -> int:
	return int(state[_white_ids[0]]) + int(state[_white_ids[1]]) * 24 \
		+ int(state[_white_ids[2]]) * 576 + int(state[_white_ids[3]]) * 13824


# ================================================================= 阶段 0：白色一层
static func solve_first_layer(state_in: PackedByteArray) -> Array[int]:
	_ensure()
	ensure_first_layer_table()
	var state := state_in.duplicate()
	var out: Array[int] = []
	if _fl_ready:
		# 精确距离表 + 梯度下降 = 最优解，几乎无耗时
		for step in 12:
			var d: int = _fl_dist[_fl_key(state)]
			if d <= 0:
				break
			for mi: int in _search_moves:
				var t := state.duplicate()
				CubeModel.apply_move_to(t, mi)
				if _fl_dist[_fl_key(t)] == d - 1:
					CubeModel.apply_move_to(state, mi)
					out.append(mi)
					break
		return out
	# 退路：IDA*
	var whole := search(state_in.duplicate(), KIND_PREFIX, 9, 4, 300000)
	if not whole.is_empty():
		return whole
	var s := state_in.duplicate()
	for k in range(1, 5):
		if _goal(s, KIND_PREFIX, k):
			continue
		var seg := search(s.duplicate(), KIND_PREFIX, 9, k, 300000)
		if seg.is_empty():
			break
		CubeModel.apply_sequence(s, seg)
		out.append_array(seg)
	return out


# ================================================================= 公式匹配
static func _try_algorithms(state: PackedByteArray, algs: Array, kind: int) -> Dictionary:
	var best_ok := false
	var best_name := ""
	var best_moves: Array[int] = []
	var empty_moves: Array[int] = []
	for alg: Dictionary in algs:
		var alg_moves := CubeModel.parse_sequence(alg["moves"])
		if alg_moves.is_empty():
			continue
		for pre in 4:
			for post in 4:
				var t := state.duplicate()
				var seq: Array[int] = []
				for i in pre:
					CubeModel.apply_move_to(t, CubeModel.U_MOVE)
					seq.append(CubeModel.U_MOVE)
				CubeModel.apply_sequence(t, alg_moves)
				seq.append_array(alg_moves)
				for i in post:
					CubeModel.apply_move_to(t, CubeModel.U_MOVE)
					seq.append(CubeModel.U_MOVE)
				if _goal(t, kind, 4):
					if not best_ok or seq.size() < best_moves.size():
						best_ok = true
						best_name = alg["name"]
						best_moves = seq
	return {"ok": best_ok, "name": best_name, "moves": best_moves if best_ok else empty_moves}


## 回退方案：用“标准公式 + AUF”做广度优先搜索（结果全部由标准公式组成，适合教学）
static func _bfs_algorithms(state: PackedByteArray, algs: Array, kind: int, max_edges: int = 4) -> Array[int]:
	var edges: Array = [{"moves": [CubeModel.U_MOVE]}]
	for alg: Dictionary in algs:
		var mv := CubeModel.parse_sequence(alg["moves"])
		if not mv.is_empty():
			edges.append({"moves": mv})
	var seen := {_state_key(state): true}
	var queue: Array = [[state, [] as Array[int], 0]]
	var head := 0
	while head < queue.size():
		var node: Array = queue[head]
		head += 1
		var cur: PackedByteArray = node[0]
		var cur_moves: Array = node[1]
		var depth: int = node[2]
		if depth >= max_edges:
			continue
		for edge: Dictionary in edges:
			var t := cur.duplicate()
			var em: Array = edge["moves"]
			CubeModel.apply_sequence(t, em)
			if _goal(t, kind, 4):
				var out: Array[int] = []
				for m in cur_moves:
					out.append(int(m))
				for m in em:
					out.append(int(m))
				return out
			var key := _state_key(t)
			if not seen.has(key):
				seen[key] = true
				var nm: Array = cur_moves.duplicate()
				nm.append_array(em)
				queue.append([t, nm, depth + 1])
	return []


# ================================================================= 规划
static func plan(state: PackedByteArray) -> Dictionary:
	_ensure()

	if _goal(state, KIND_SOLVED, 4):
		var done_moves: Array[int] = []
		return {
			"phase": PHASE_DONE,
			"phase_name": "已完成",
			"detail": "魔方已经复原，可以打乱后继续练习。",
			"alg_name": "",
			"moves": done_moves,
			"moves_text": "",
		}

	if not CubeModel.first_layer_solved(state):
		var moves := solve_first_layer(state)
		var missing := 4 - CubeModel.first_layer_count(state)
		return {
			"phase": 0,
			"phase_name": "第 1 步 · 复原白色一层",
			"detail": "目标：4 个白色角块全部朝下，并且侧面颜色两两对齐（还有 %d 个角块没归位）。" % missing,
			"alg_name": "",
			"moves": moves,
			"moves_text": CubeModel.sequence_to_string(moves),
		}

	if not CubeModel.top_oriented(state):
		var res := _try_algorithms(state, OLL_ALGS, KIND_LAYER_TOP)
		if not res["ok"]:
			var mv := _bfs_algorithms(state, OLL_ALGS, KIND_LAYER_TOP, 4)
			res = {"ok": not mv.is_empty(), "name": "公式组合（连续使用标准公式）", "moves": mv}
		return {
			"phase": 1,
			"phase_name": "第 2 步 · 顶层黄色面（OLL 朝向）",
			"detail": "目标：把 4 个黄色贴纸全部翻到顶面（先不管位置）。",
			"alg_name": res["name"],
			"moves": res["moves"],
			"moves_text": CubeModel.sequence_to_string(res["moves"]),
		}

	var res2 := _try_algorithms(state, PLL_ALGS, KIND_SOLVED)
	if not res2["ok"]:
		var mv2 := _bfs_algorithms(state, PLL_ALGS, KIND_SOLVED, 4)
		res2 = {"ok": not mv2.is_empty(), "name": "公式组合（连续使用标准公式）", "moves": mv2}
	return {
		"phase": 2,
		"phase_name": "第 3 步 · 顶层角块归位（PLL）",
		"detail": "目标：交换顶层角块，让每一面的颜色完全一致。",
		"alg_name": res2["name"],
		"moves": res2["moves"],
		"moves_text": CubeModel.sequence_to_string(res2["moves"]),
	}


## 一次性算出完整解法（按阶段分组）
static func full_plan(state_in: PackedByteArray, max_steps: int = 8) -> Array:
	var state := state_in.duplicate()
	var out: Array = []
	for step in max_steps:
		var p := plan(state)
		if int(p["phase"]) == PHASE_DONE:
			break
		var moves: Array = p["moves"]
		if moves.is_empty():
			break
		out.append(p)
		CubeModel.apply_sequence(state, moves)
	return out
