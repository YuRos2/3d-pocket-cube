extends SceneTree

## 压力测试：大量随机打乱 → 完整求解，统计成功率与耗时。
## godot --headless --path . --script res://tests/stress.gd

func _solved() -> PackedByteArray:
	var s := PackedByteArray()
	s.resize(8)
	for id in 8:
		s[id] = int(CubeModel.POS_INDEX[CubeModel.HOME[id]]) * 3
	return s


func _init() -> void:
	seed(12345)
	CubeModel.ensure()
	CubeSolver._ensure()
	var t0 := Time.get_ticks_msec()
	CubeSolver.ensure_first_layer_table()
	print("一层距离表构建：%d ms" % (Time.get_ticks_msec() - t0))

	var n_total := 400
	var fails := 0
	var worst := 0
	var total := 0
	var over50 := 0
	var max_moves := 0
	for n in n_total:
		var s := _solved()
		var scr := CubeModel.random_scramble(12)
		CubeModel.apply_sequence(s, scr)
		var t1 := Time.get_ticks_msec()
		var used := 0
		var guard := 0
		while not CubeModel.is_solved(s) and guard < 8:
			guard += 1
			var p := CubeSolver.plan(s)
			var mv: Array = p["moves"]
			if mv.is_empty():
				fails += 1
				print("  求解失败: ", CubeModel.sequence_to_string(scr))
				break
			used += mv.size()
			CubeModel.apply_sequence(s, mv)
		if not CubeModel.is_solved(s):
			fails += 1
			print("  未复原: ", CubeModel.sequence_to_string(scr))
		var dt := Time.get_ticks_msec() - t1
		worst = maxi(worst, dt)
		total += dt
		if dt > 50:
			over50 += 1
		max_moves = maxi(max_moves, used)
	print("%d 次随机复原：失败 %d，平均 %d ms，最慢 %d ms，>50ms 的次数 %d，最长解法 %d 步" % [
		n_total, fails, total / n_total, worst, over50, max_moves])
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit()
