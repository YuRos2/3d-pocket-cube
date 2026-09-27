extends Node

## 面向中小学生的交互自测：验证“下一步提示 / 走一步 / 步骤进度 / 庆祝 / 成绩存档 / 音效开关”。
## 运行：godot --headless --path . res://tests/kids_ui.tscn

var _fails := 0
var _main: Node


func _ready() -> void:
	Engine.max_fps = 0
	await get_tree().process_frame
	await _run()
	print("--------------------------------------------------")
	print("KIDS_UI: %s（失败 %d）" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("  [FAIL] ", msg)


func _wait_idle(max_frames: int = 6000) -> void:
	var g := 0
	while (_main._ui_busy or _main.cube.is_busy()) and g < max_frames:
		g += 1
		await get_tree().process_frame


func _run() -> void:
	# 备份并清空可能存在的旧成绩，保证测试干净；结束时恢复
	var record_path := "user://pocketcube_record.cfg"
	var had_record := FileAccess.file_exists(record_path)
	var backup := PackedByteArray()
	if had_record:
		backup = FileAccess.get_file_as_bytes(record_path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(record_path))
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
	_check(cube != null and ui != null, "场景构建完成")
	# —— 顶栏“自动复原”按钮会在运行时变成“停止” ——
	ui.set_auto_running(true)
	_check(ui._solve_button.text.contains("停止"), "运行时按钮变成“停止”")
	ui.set_auto_running(false)
	_check(ui._solve_button.text.contains("自动复原"), "停止后按钮恢复“自动复原”")

	# —— 步骤进度：复原状态应显示 3 步全完成 ——
	ui.set_steps(3)
	var all_done := true
	for t: Label in ui._step_texts:
		if not t.text.begins_with("✅"):
			all_done = false
	_check(all_done, "三步进度可全部标记完成")
	ui.set_steps(0)
	_check(ui._step_texts[0].text.begins_with("👉"), "当前步骤会高亮")

	# —— 打乱后提示：应给出“下一步” ——
	_main._load_lesson(2) # 第 3 课（随机打乱）
	await get_tree().process_frame
	cube.speed = 40.0
	await _main._on_hint()
	await get_tree().process_frame
	_check(ui._next_label.text.begins_with("下一步："), "提示后有“下一步”文字")
	_check(not ui._step_button.disabled, "提示后“走一步”可用")

	# —— 走一步：只走一步、不计步数 ——
	var before_moves: int = _main._move_count
	var before_code := cube.model.codes.duplicate()
	await _main._on_step()
	await _wait_idle()
	var changed := false
	for i in 8:
		if cube.model.codes[i] != before_code[i]:
			changed = true
	_check(changed, "“走一步”确实转动了魔方")
	_check(_main._move_count == before_moves, "“走一步”不计入步数")

	# —— 走一步之后仍能继续分析，说明状态一致 ——
	await _main._on_hint()
	await get_tree().process_frame
	_check(_main._current_plan.has("moves"), "走一步后仍能分析局面")

	# —— 每一步都跟随提示，应当能一路走到复原 ——
	_main._load_lesson(2)
	await get_tree().process_frame
	var guard := 0
	while not CubeModel.is_solved(cube.model.codes) and guard < 80:
		guard += 1
		if ui._step_button.disabled:
			await _main._on_hint()
			await get_tree().process_frame
		if ui._step_button.disabled:
			break
		await _main._on_step()
		await _wait_idle()
	_check(CubeModel.is_solved(cube.model.codes), "一直点“走一步”最终能复原")

	# —— 庆祝动画不应报错，并能正常结束 ——
	ui.celebrate("测试")
	await get_tree().process_frame
	ui.celebrate("再测一次")

	# —— 计时复原后应写入最好成绩 ——
	_main._load_lesson(6) # 第 7 课（计时挑战）
	await get_tree().process_frame
	cube.reset_to_solved()
	ui.update_net(cube.model.codes)
	_main._move_count = 12
	_main._timing = true
	_main._time_start = Time.get_ticks_msec() / 1000.0 - 9.5
	_main._check_solved()
	await get_tree().process_frame
	_check(ui._record_label.text.contains("最好成绩"), "破纪录后显示最好成绩")
	var cf := ConfigFile.new()
	var ok := cf.load(record_path) == OK
	_check(ok and cf.has_section_key("record", "best_time"), "最好成绩已存盘")
	_check(FileAccess.file_exists(record_path), "存档文件已生成")

	# —— 音效开关 ——
	_main.feedback.set_enabled(false)
	_main.feedback.play_success()
	_main.feedback.play_turn()
	_main.feedback.set_enabled(true)
	_check(true, "音效开关不报错")

	# —— 自动复原仍可正常跑完 ——
	_main._load_lesson(5) # 第 6 课（随机）
	await get_tree().process_frame
	_main._on_solve()
	var g2 := 0
	while (_main._auto or _main._ui_busy or cube.is_busy()) and g2 < 6000:
		g2 += 1
		await get_tree().process_frame
	_check(CubeModel.is_solved(cube.model.codes), "自动复原后已复原")
	_check(ui._solve_button.text.contains("自动复原"), "自动复原结束后按钮恢复")

	# 清理测试成绩，避免影响真实游玩（有旧成绩就恢复）
	if had_record:
		var f := FileAccess.open(record_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(record_path))
