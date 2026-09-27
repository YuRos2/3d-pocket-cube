extends SceneTree

## 快速逻辑自测（几十秒内跑完）
## godot --headless --path . --script res://tests/test_logic.gd

var _fail := 0
var _oll_named := 0
var _oll_fb := 0
var _pll_named := 0
var _pll_fb := 0


func _init() -> void:
	var t := Time.get_ticks_msec()
	seed(7)
	CubeModel.ensure()
	CubeSolver._ensure()
	var tb := Time.get_ticks_msec()
	CubeSolver.ensure_first_layer_table()
	print("[%dms] 一层距离表构建完成" % (Time.get_ticks_msec() - tb))

	_test_tables()
	print("[%dms] 数据表 OK" % (Time.get_ticks_msec() - t))

	_test_basic()
	print("[%dms] 基本转动 OK" % (Time.get_ticks_msec() - t))

	_test_first_layer(15)
	print("[%dms] 白色一层求解 OK" % (Time.get_ticks_msec() - t))

	_test_random_solves(20)
	print("[%dms] 随机求解 OK" % (Time.get_ticks_msec() - t))

	_test_oll_coverage()
	_test_pll_coverage()

	print("--------------------------------------------------")
	print("OLL: 公式 %d / 回退 %d   PLL: 公式 %d / 回退 %d" % [_oll_named, _oll_fb, _pll_named, _pll_fb])
	print("总耗时 %d ms   失败 %d" % [Time.get_ticks_msec() - t, _fail])
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	quit()


func _check(c: bool, m: String) -> void:
	if not c:
		_fail += 1
		print("  [FAIL] ", m)


func _solved() -> PackedByteArray:
	var s := PackedByteArray()
	s.resize(8)
	for id in 8:
		s[id] = int(CubeModel.POS_INDEX[CubeModel.HOME[id]]) * 3
	return s


func _test_tables() -> void:
	for id in 8:
		for code in 24:
			var b: Basis = CubeModel.CODE_BASIS[id][code]
			var pos := CubeModel.to_vec3i(b * Vector3(CubeModel.HOME[id]))
			var re: int = int(CubeModel.POS_INDEX[pos]) * 3 + CubeModel.orientation_of(b, CubeModel.HOME[id])
			_check(re == code, "code 往返 id=%d code=%d" % [id, code])
	for mi in CubeModel.MOVES.size():
		var q: int = CubeModel.MOVES[mi]["quarter"]
		var s := _solved()
		for i in (2 if q == 2 else 4):
			CubeModel.apply_move_to(s, mi)
		_check(CubeModel.is_solved(s), "%s 自乘未复原" % CubeModel.move_name(mi))
	# 启发式表抽查
	_check(CubeSolver._dist_white[0] == 0 and CubeSolver._dist_white.size() == 24, "白色角块距离表")
	_check(CubeSolver._dist_pos[3].size() == 4096, "位置表大小")


func _test_basic() -> void:
	var s := _solved()
	for i in 6:
		CubeModel.apply_sequence(s, CubeModel.parse_sequence("R U R' U'"))
	_check(CubeModel.is_solved(s), "R U R' U' x6")
	_check(CubeModel.invert_sequence("R U2 F'") == "F U2 R'", "逆公式")
	var s2 := _solved()
	CubeModel.apply_sequence(s2, CubeModel.parse_sequence("R"))
	_check(CubeModel.first_layer_count(s2) == 2, "R 后白色角块数=%d" % CubeModel.first_layer_count(s2))


func _test_first_layer(count: int) -> void:
	var worst := 0
	var slow := 0
	var t0 := Time.get_ticks_msec()
	for n in count:
		var s := _solved()
		CubeModel.apply_sequence(s, CubeModel.random_scramble(12))
		var t1 := Time.get_ticks_msec()
		var mv := CubeSolver.solve_first_layer(s)
		var dt := Time.get_ticks_msec() - t1
		slow = maxi(slow, dt)
		worst = maxi(worst, mv.size())
		CubeModel.apply_sequence(s, mv)
		_check(CubeModel.first_layer_solved(s), "白色一层未复原 %s" % CubeModel.sequence_to_string(mv))
	print("     一层最长 %d 步，单次最慢 %d ms" % [worst, slow])


func _test_random_solves(count: int) -> void:
	var slow := 0
	for n in count:
		var s := _solved()
		var scr := CubeModel.random_scramble(12)
		CubeModel.apply_sequence(s, scr)
		var t1 := Time.get_ticks_msec()
		var guard := 0
		while not CubeModel.is_solved(s) and guard < 8:
			guard += 1
			var p := CubeSolver.plan(s)
			var moves: Array = p["moves"]
			if moves.is_empty():
				_check(false, "求解失败 %s" % CubeModel.sequence_to_string(scr))
				break
			CubeModel.apply_sequence(s, moves)
		slow = maxi(slow, Time.get_ticks_msec() - t1)
		_check(CubeModel.is_solved(s), "未复原 %s" % CubeModel.sequence_to_string(scr))
	print("     完整求解单次最慢 %d ms" % slow)


func _test_oll_coverage() -> void:
	var top := CubeModel.top_cubie_ids()
	var t0 := Time.get_ticks_msec()
	for o0 in 3:
		for o1 in 3:
			for o2 in 3:
				var oris := [o0, o1, o2, posmod(-(o0 + o1 + o2), 3)]
				if oris.count(0) == 4:
					continue
				var s := _solved()
				for i in 4:
					s[top[i]] = int(CubeModel.POS_INDEX[CubeModel.HOME[top[i]]]) * 3 + oris[i]
				var p := CubeSolver.plan(s)
				var name := String(p["alg_name"])
				if name == "通用解法" or name == "":
					_oll_fb += 1
				else:
					_oll_named += 1
				_check(int(p["phase"]) == 1, "OLL 阶段判定 %s" % str(oris))
				CubeModel.apply_sequence(s, p["moves"])
				_check(CubeModel.first_layer_solved(s) and CubeModel.top_oriented(s), "OLL 未完成 %s / %s" % [str(oris), name])
	print("[%dms] OLL 27 情况覆盖完成" % (Time.get_ticks_msec() - t0))


func _test_pll_coverage() -> void:
	var top := CubeModel.top_cubie_ids()
	var t0 := Time.get_ticks_msec()
	var n := 0
	for perm: Array in _perms(top):
		var s := _solved()
		for i in 4:
			s[perm[i]] = top[i] * 3
		if CubeModel.is_solved(s):
			continue
		n += 1
		var p := CubeSolver.plan(s)
		var name := String(p["alg_name"])
		if name == "通用解法" or name == "":
			_pll_fb += 1
		else:
			_pll_named += 1
		_check(int(p["phase"]) == 2, "PLL 阶段判定 %s" % str(perm))
		CubeModel.apply_sequence(s, p["moves"])
		_check(CubeModel.is_solved(s), "PLL 未复原 %s / %s" % [str(perm), name])
	print("[%dms] PLL %d 情况覆盖完成" % [Time.get_ticks_msec() - t0, n])


func _perms(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var out: Array = []
	for i in items.size():
		var rest := items.duplicate()
		var head: Variant = rest.pop_at(i)
		for tail: Array in _perms(rest):
			var p: Array = [head]
			p.append_array(tail)
			out.append(p)
	return out
