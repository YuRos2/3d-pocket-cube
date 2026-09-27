extends Node

## 集成测试：真正加载 main.tscn，模拟“打乱 → 教练提示 → 自动复原 → 切换全部课程”
## 运行方式：godot --headless --path . res://tests/integration.tscn

var _fails := 0
var _main: Node


func _ready() -> void:
	Engine.max_fps = 0
	await get_tree().process_frame
	await _run()
	print("--------------------------------------------------")
	print("INTEGRATION: %s（失败 %d）" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("  [FAIL] ", msg)


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	if _main.get("cube") == null or _main.get("ui") == null:
		_fails += 1
		print("  [FAIL] main.gd 未能加载（脚本错误）")
		return

	var cube: CubeView = _main.cube
	var ui: GameUI = _main.ui
	_check(cube != null, "CubeView 创建")
	_check(ui != null, "GameUI 创建")
	_check(cube.get_child_count() >= 8, "8 个角块节点")
	_check(CubeModel.is_solved(cube.model.codes), "初始为已复原状态")
	_check(ui.is_panel_visible(), "教学面板默认可见")

	# 视觉与逻辑一致性
	var ok_visual := true
	for id in 8:
		var code: int = cube.model.codes[id]
		var want := Transform3D(CubeModel.CODE_BASIS[id][code], Vector3(CubeModel.pos_of(code)) * CubeView.SPACING)
		var got: Transform3D = (cube._cubies[id] as Node3D).transform
		if not got.is_equal_approx(want):
			ok_visual = false
	_check(ok_visual, "角块摆放与逻辑状态一致")

	cube.speed = 30.0 # 测试时加快动画

	# —— 教练提示（打乱后）——
	var scr := CubeModel.random_scramble(12)
	cube.apply_instant(scr)
	_check(not CubeModel.is_solved(cube.model.codes), "打乱后不是复原状态")
	var plan: Dictionary = CubeSolver.plan(cube.model.codes)
	_check(int(plan["phase"]) == 0, "打乱后应处于阶段 0，实际 %d" % int(plan["phase"]))
	_check(not (plan["moves"] as Array).is_empty(), "阶段 0 应给出操作序列")

	# —— 自动复原（走完整 UI 流程）——
	_main._on_solve()
	var guard := 0
	while (_main._auto or _main._ui_busy or cube.is_busy()) and guard < 6000:
		guard += 1
		await get_tree().process_frame
	_check(CubeModel.is_solved(cube.model.codes), "自动复原后魔方已复原")
	_check(cube._queue.is_empty(), "操作队列已清空")

	# —— 全部课程都能加载 ——
	for i in GameLessons.all().size():
		_main._load_lesson(i)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_main._lesson_index == i, "课程 %d 加载" % i)
		var state: PackedByteArray = cube.model.codes
		_check(state.size() == 8, "课程 %d 后状态合法" % i)
		match i:
			3:
				_check(CubeModel.first_layer_solved(state), "第 4 课应已摆好白色一层")
				_check(not CubeModel.top_oriented(state), "第 4 课顶面应未完成")
			4:
				_check(CubeModel.first_layer_solved(state), "第 5 课应已摆好白色一层")
				_check(CubeModel.top_oriented(state), "第 5 课顶面应已全黄")
				_check(not CubeModel.is_solved(state), "第 5 课应还差最后一步")

	# —— 每一课都执行一次“演示” ——
	for i in GameLessons.all().size():
		_main._load_lesson(i)
		await get_tree().process_frame
		_main._on_demo()
		var g2 := 0
		while (_main._ui_busy or cube.is_busy()) and g2 < 6000:
			g2 += 1
			await get_tree().process_frame
		await get_tree().process_frame
		_check(cube.model.codes.size() == 8, "课程 %d 演示后状态合法" % i)

	# —— 撤销 ——
	_main._load_lesson(1)
	await get_tree().process_frame
	cube.enqueue(CubeModel.NAME_TO_MOVE["R"])
	var g4 := 0
	while cube.is_busy() and g4 < 2000:
		g4 += 1
		await get_tree().process_frame
	await get_tree().process_frame
	_check(_main._move_count == 1, "R 后步数为 1，实际 %d" % _main._move_count)
	_main._on_undo()
	var g3 := 0
	while (_main._ui_busy or cube.is_busy()) and g3 < 3000:
		g3 += 1
		await get_tree().process_frame
	_check(CubeModel.is_solved(cube.model.codes), "撤销后回到复原状态")

	# —— 拖动到转动层的推断 ——
	var cam: Camera3D = _main.camera
	# UFR 角块（逻辑坐标 (1,1,1)，世界坐标 0.5）的“前面”中心点
	var p_front := Vector3(0.25, 0.25, 0.495)
	var c_ufr := Vector3(1, 1, 1)
	var c_dfr := Vector3(1, -1, 1)
	var c_ufl := Vector3(-1, 1, 1)
	var p0 := cam.unproject_position(p_front)
	var drag_right := Vector2(80, 0)
	var drag_left := Vector2(-80, 0)
	var drag_down := Vector2(0, 80)
	var drag_up := Vector2(0, -80)
	_check(CubeModel.move_name(cube._resolve_move(Vector3(0, 0, 1), p_front, c_ufr, drag_right)) == "U'",
		"前上角向右拖 = U'")
	_check(CubeModel.move_name(cube._resolve_move(Vector3(0, 0, 1), p_front, c_dfr, drag_right)) == "D",
		"前下角向右拖 = D")
	_check(CubeModel.move_name(cube._resolve_move(Vector3(0, 0, 1), p_front, c_ufr, drag_left)) == "U",
		"前上角向左拖 = U")
	_check(CubeModel.move_name(cube._resolve_move(Vector3(0, 0, 1), p_front, c_ufr, drag_down)) == "R'",
		"前右角向下拖 = R'")
	_check(CubeModel.move_name(cube._resolve_move(Vector3(0, 0, 1), p_front, c_ufl, drag_down)) == "L",
		"前左角向下拖 = L")
	_check(CubeModel.move_name(cube._resolve_move(Vector3(0, 0, 1), p_front, c_ufr, drag_up)) == "R",
		"前右角向上拖 = R")
	# 顶面拖动（法线朝上）
	var p_top := Vector3(0.25, 0.495, 0.25)
	_check(CubeModel.move_name(cube._resolve_move(Vector3(0, 1, 0), p_top, c_ufr, drag_right)) == "F",
		"顶面前右角向右拖 = F")

	# —— 展开图 ——
	ui.update_net(cube.model.codes)
	_check(ui._net.codes.size() == 8, "展开图状态已同步")
