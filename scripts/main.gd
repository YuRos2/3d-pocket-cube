extends Node3D

## 3D 二阶魔方 · 教学版
## 负责：场景搭建（环境/灯光/相机）、教学课程流程、教练提示、计时与统计。

const LESSONS := preload("res://scripts/lessons.gd")

var cube: CubeView
var ui: GameUI
var rig: Node3D
var camera: Camera3D
var feedback: Feedback

const RECORD_PATH := "user://pocketcube_record.cfg"
const FACE_CN := {"R": "🟥 右面", "L": "🟧 左面", "U": "🟨 顶面", "D": "⬜ 底面", "F": "🟩 前面", "B": "🟦 后面"}

var _lessons: Array = []
var _lesson_index := 0
var _current_demo: Array[int] = []
var _current_plan := {}
var _guide_moves: Array[int] = []  ## “走一步”正在跟随的引导序列

var _history: Array[int] = []
var _move_count := 0
var _timing := false
var _time_start := 0.0
var _elapsed_fixed := 0.0
var _armed := false
var _silent := false
var _auto := false
var _ui_busy := false
var _best_time := -1.0
var _best_moves := 0


# ================================================================= 初始化
func _ready() -> void:
	randomize()
	DisplayServer.window_set_title("二阶魔方 3D · 教学版")
	CubeModel.ensure()
	CubeSolver._ensure()
	CubeSolver.start_first_layer_build() # 后台预计算“白色一层”精确解表
	_build_world()
	_build_cube()
	feedback = Feedback.new()
	feedback.name = "Feedback"
	add_child(feedback)
	_build_ui()
	_load_record()

	_lessons = LESSONS.all()
	var titles: Array = []
	for l: Dictionary in _lessons:
		titles.append(l["title"])
	ui.set_lessons(titles)
	_load_lesson(0)
	ui.set_moves(0)
	ui.set_timer(_fmt(0.0))


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.13, 0.19)
	sky_mat.sky_horizon_color = Color(0.22, 0.26, 0.32)
	sky_mat.ground_horizon_color = Color(0.16, 0.18, 0.22)
	sky_mat.ground_bottom_color = Color(0.05, 0.06, 0.08)
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_energy_multiplier = 0.7
	sky_mat.sun_angle_max = 14.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.ambient_light_sky_contribution = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.8
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 34, 0)
	key.light_energy = 1.9
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 24.0
	key.shadow_blur = 0.6
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-14, -125, 0)
	fill.light_energy = 0.65
	fill.light_color = Color(0.66, 0.76, 1.0)
	add_child(fill)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(48, 48)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.075, 0.085, 0.105)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position.y = -1.75
	add_child(ground)

	rig = Node3D.new()
	rig.name = "CameraRig"
	rig.rotation = Vector3(deg_to_rad(-24), deg_to_rad(32), 0)
	add_child(rig)

	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.1
	camera.far = 100.0
	camera.position = Vector3(0, 0, 5.6)
	rig.add_child(camera)
	camera.make_current()


func _build_cube() -> void:
	cube = CubeView.new()
	cube.name = "Cube"
	cube.speed = 1.6
	add_child(cube)
	cube.camera = camera
	cube.rig = rig
	cube.move_done.connect(_on_move_done)


func _build_ui() -> void:
	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.scramble_requested.connect(_on_scramble)
	ui.undo_requested.connect(_on_undo)
	ui.hint_requested.connect(_on_hint)
	ui.solve_requested.connect(_on_solve)
	ui.stop_requested.connect(_on_stop)
	ui.reset_requested.connect(_on_reset_cube)
	ui.view_reset_requested.connect(func() -> void: cube.reset_view())
	ui.demo_requested.connect(_on_demo)
	ui.step_requested.connect(_on_step)
	ui.lesson_changed.connect(_load_lesson)
	ui.speed_changed.connect(func(v: float) -> void: cube.speed = v)
	ui.sound_toggled.connect(func(on: bool) -> void: feedback.set_enabled(on))


# ================================================================= 主循环
func _process(_delta: float) -> void:
	# 分帧预计算“白色一层”精确解表，不卡主线程
	CubeSolver.first_layer_build_step(7.0)
	if _timing:
		ui.set_timer(_fmt(_elapsed()))


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			_on_scramble()
		KEY_Z:
			_on_undo()
		KEY_H:
			_on_hint()
		KEY_S:
			_on_solve()
		KEY_V:
			cube.reset_view()
		KEY_ESCAPE, KEY_T:
			ui.toggle_panel()
		KEY_U:
			_key_turn("U", k.shift_pressed)
		KEY_D:
			_key_turn("D", k.shift_pressed)
		KEY_L:
			_key_turn("L", k.shift_pressed)
		KEY_R:
			_key_turn("R", k.shift_pressed)
		KEY_F:
			_key_turn("F", k.shift_pressed)
		KEY_B:
			_key_turn("B", k.shift_pressed)


func _key_turn(face: String, shift: bool) -> void:
	if _auto:
		return
	var name := face + ("'" if shift else "")
	var mi := int(CubeModel.NAME_TO_MOVE.get(name, -1))
	if mi >= 0:
		cube.enqueue(mi)


# ================================================================= 计时 / 统计
func _elapsed() -> float:
	if _timing:
		return Time.get_ticks_msec() / 1000.0 - _time_start
	return _elapsed_fixed


static func _fmt(t: float) -> String:
	var m := int(t) / 60
	return "%02d:%05.2f" % [m, t - m * 60]


func _start_timer() -> void:
	_timing = true
	_time_start = Time.get_ticks_msec() / 1000.0


func _stop_timer() -> void:
	_elapsed_fixed = _elapsed()
	_timing = false


func _reset_counters() -> void:
	_history.clear()
	_move_count = 0
	_timing = false
	_elapsed_fixed = 0.0
	_armed = true
	ui.set_moves(0)
	ui.set_timer(_fmt(0.0))
	ui.set_history("")


func _history_text() -> String:
	if _history.is_empty():
		return ""
	var parts := PackedStringArray()
	var start: int = maxi(0, _history.size() - 12)
	for i in range(start, _history.size()):
		parts.append(CubeModel.move_name(_history[i]))
	return " ".join(parts)


# ================================================================= 转动回调
func _on_move_done(mi: int) -> void:
	ui.update_net(cube.model.codes)
	feedback.play_turn()
	if _silent:
		return
	_guide_moves.clear() # 玩家自己动手后，旧引导作废
	_move_count += 1
	_history.append(mi)
	ui.set_moves(_move_count)
	ui.set_history(_history_text())
	if _armed:
		_armed = false
		_start_timer()
	_check_solved()


func _check_solved() -> void:
	if not CubeModel.is_solved(cube.model.codes):
		return
	if _timing:
		_stop_timer()
		var t := _elapsed_fixed
		ui.show_toast("🎉 复原成功！用时 %s，共 %d 步" % [_fmt(t), _move_count], 4.0)
		feedback.play_success()
		ui.celebrate(_praise())
		_maybe_save_record(t, _move_count)
	else:
		ui.show_toast("✨ 已经复原！点“🎲 打乱”继续练习。", 2.4)
	_refresh_coach(false)


func _praise() -> String:
	var words := ["太棒了！", "好厉害！", "你真棒！", "完成啦！", "超级棒！", "干得漂亮！"]
	return words[randi() % words.size()]


func _record_text() -> String:
	if _best_time < 0.0:
		return "🏆 还没有记录，快来挑战！"
	return "🏆 最好成绩：%s / %d 步" % [_fmt(_best_time), _best_moves]


func _load_record() -> void:
	var cf := ConfigFile.new()
	if cf.load(RECORD_PATH) == OK:
		_best_time = float(cf.get_value("record", "best_time", -1.0))
		_best_moves = int(cf.get_value("record", "best_moves", 0))
	ui.set_record(_record_text())


func _maybe_save_record(t: float, moves: int) -> void:
	if moves < 4:
		return
	if _best_time >= 0.0 and t >= _best_time - 0.001:
		return
	_best_time = t
	_best_moves = moves
	var cf := ConfigFile.new()
	cf.set_value("record", "best_time", _best_time)
	cf.set_value("record", "best_moves", _best_moves)
	cf.save(RECORD_PATH)
	ui.set_record(_record_text())


# ================================================================= 打乱 / 撤销
func _on_scramble() -> void:
	_stop_auto()
	_guide_moves.clear()
	feedback.play_click()
	var moves := CubeModel.random_scramble(12)
	cube.apply_instant(moves)
	_reset_counters()
	ui.update_net(cube.model.codes)
	ui.show_toast("打乱：" + CubeModel.sequence_to_string(moves), 2.2)
	_refresh_coach(false)


func _on_undo() -> void:
	if _auto or _ui_busy or _history.is_empty() or cube.is_busy():
		return
	_ui_busy = true
	_guide_moves.clear()
	var mi: int = _history.pop_back()
	_silent = true
	feedback.play_undo()
	cube.enqueue(CubeModel.inverse_of(mi))
	await cube.idle
	_silent = false
	_ui_busy = false
	_move_count = maxi(0, _move_count - 1)
	ui.set_moves(_move_count)
	ui.set_history(_history_text())
	ui.update_net(cube.model.codes)
	_refresh_coach(false)


# ================================================================= 教练 / 演示
func _compute_plan() -> Dictionary:
	ui.set_progress("正在分析当前局面…")
	await get_tree().process_frame
	var plan := CubeSolver.plan(cube.model.codes)
	_current_plan = plan
	return plan


func _show_plan(plan: Dictionary) -> void:
	var text := "[b]%s[/b]\n%s" % [plan["phase_name"], plan["detail"]]
	var alg_name := String(plan["alg_name"])
	var moves: Array = plan["moves"]
	if alg_name != "":
		text += "\n[color=#b45309]推荐公式：[/color]%s" % alg_name
	if not moves.is_empty():
		text += "\n[color=#1d4ed8]操作序列（%d 步）：[/color][code]%s[/code]" % [
			moves.size(), CubeModel.sequence_to_string(moves)
		]
	ui.set_coach(text, not moves.is_empty())
	ui.set_progress(_phase_progress_text())
	if moves.is_empty():
		ui.set_next_move("下一步：已经完成啦 ✅", false)
	else:
		ui.set_next_move("下一步：%s" % _move_text(int(moves[0])), true)


## 把转动描述成小朋友看得懂的话
func _move_text(mi: int) -> String:
	var name := CubeModel.move_name(mi)
	var face := name.substr(0, 1)
	var suffix := name.substr(1)
	var dir := "顺时针"
	if suffix == "'":
		dir = "逆时针"
	elif suffix == "2":
		dir = "转 180°"
	return "%s %s" % [String(FACE_CN.get(face, face)), dir]


func _phase_progress_text() -> String:
	var st: PackedByteArray = cube.model.codes
	if CubeModel.is_solved(st):
		return "状态：已复原 ✓"
	var fl := CubeModel.first_layer_count(st)
	if fl < 4:
		return "阶段 1 / 3 · 白色一层：%d / 4 个角块已归位" % fl
	var tc := CubeModel.top_oriented_count(st)
	if tc < 4:
		return "阶段 2 / 3 · 顶层黄面（OLL）：%d / 4 个黄贴纸朝上" % tc
	return "阶段 3 / 3 · 顶层归位（PLL）：就差最后一步"


func _phase_index(state: PackedByteArray) -> int:
	if CubeModel.is_solved(state):
		return 3
	if CubeModel.first_layer_count(state) < 4:
		return 0
	if CubeModel.top_oriented_count(state) < 4:
		return 1
	return 2


func _refresh_coach(compute: bool) -> void:
	ui.set_progress(_phase_progress_text())
	var st: PackedByteArray = cube.model.codes
	ui.set_steps(_phase_index(st))
	if CubeModel.is_solved(st):
		ui.set_coach("[b]魔方已经复原！[/b]\n点“🎲 打乱”换一个局面，或者继续学下一课。", _current_demo.size() > 0)
		ui.set_next_move("下一步：已经完成啦 ✅", false)
		return
	if CubeModel.first_layer_count(st) < 4:
		ui.set_coach("目标：把 4 个白色贴纸都转到[b]下面[/b]，还要让侧面颜色两两对齐。\n不知道怎么办？点上面的 [b]💡 提示[/b] 吧！", true)
		ui.set_next_move("下一步：点“💡 提示”看看该怎么转", false)
		return
	if CubeModel.top_oriented_count(st) < 4:
		ui.set_coach("目标：把 4 个黄色贴纸都翻到[b]顶面[/b]（这一步只看朝向）。\n点 [b]💡 提示[/b] 会自动识别属于哪种情况。", true)
		ui.set_next_move("下一步：点“💡 提示”看看该怎么转", false)
		return
	ui.set_coach("目标：交换顶层角块，让每一面颜色一致。\n点 [b]💡 提示[/b] 就能拿到对应的公式。", true)
	ui.set_next_move("下一步：点“💡 提示”看看该怎么转", false)


func _on_hint() -> void:
	var plan: Dictionary = await _compute_plan()
	_show_plan(plan)
	_set_guide_from(plan)


## 把整套引导序列记下来，让“走一步”可以稳定地一步一步跟着走
func _set_guide_from(plan: Dictionary) -> void:
	_guide_moves.clear()
	for m: Variant in plan["moves"]:
		_guide_moves.append(int(m))


func _on_demo() -> void:
	if _auto or _ui_busy:
		return
	_ui_busy = true
	_guide_moves.clear()
	var plan: Dictionary = await _compute_plan()
	var moves: Array = plan["moves"]
	var label := "%s（%d 步）" % [plan["phase_name"], moves.size()]
	if moves.is_empty() and not _current_demo.is_empty():
		moves = _current_demo
		label = "演示公式 " + CubeModel.sequence_to_string(moves)
	_show_plan(plan)
	if moves.is_empty():
		_ui_busy = false
		ui.show_toast("当前没有需要执行的操作 🙂")
		return
	_stop_timer()
	ui.show_toast("演示：" + label, 2.2)
	_silent = true
	cube.enqueue_all(moves)
	await cube.idle
	_silent = false
	_ui_busy = false
	ui.update_net(cube.model.codes)
	_check_solved()
	_refresh_coach(false)


## 只帮小朋友走一步（不计入步数，纯示范）
## 优先沿着已经验证过的引导序列走，避免在 OLL/PLL 阶段来回摆动。
func _on_step() -> void:
	if _auto or _ui_busy or cube.is_busy():
		return
	_ui_busy = true
	if _guide_moves.is_empty():
		var plan: Dictionary = await _compute_plan()
		_show_plan(plan)
		_set_guide_from(plan)
	if _guide_moves.is_empty():
		_ui_busy = false
		ui.show_toast("这一步不用转，点“🎬 帮我做完这一步”吧 🙂")
		return
	var mi: int = _guide_moves.pop_front()
	ui.show_toast("一起转：%s" % _move_text(mi), 1.8)
	feedback.play_click()
	_silent = true
	cube.enqueue(mi)
	await cube.idle
	_silent = false
	_ui_busy = false
	ui.update_net(cube.model.codes)
	_check_solved()
	_refresh_coach(false)
	if not CubeModel.is_solved(cube.model.codes):
		if _guide_moves.is_empty():
			ui.set_next_move("下一步：点“💡 提示”继续", false)
		else:
			ui.set_next_move("下一步：%s" % _move_text(_guide_moves[0]), true)


# ================================================================= 自动复原
func _on_solve() -> void:
	if _auto or _ui_busy:
		return
	_auto = true
	_guide_moves.clear()
	_stop_timer()
	cube.input_enabled = false
	ui.set_auto_running(true)
	var saved_speed := cube.speed
	cube.speed = maxf(saved_speed, 2.6) # 自动演示时加快转动
	ui.show_toast("自动复原开始（层先法）", 2.0)
	while _auto and not CubeModel.is_solved(cube.model.codes):
		var plan: Dictionary = await _compute_plan()
		if int(plan["phase"]) == CubeSolver.PHASE_DONE:
			break
		var moves: Array = plan["moves"]
		if moves.is_empty():
			ui.show_toast("求解失败，请点“🎲 打乱”后再试一次", 3.0)
			break
		_show_plan(plan)
		_silent = true
		cube.enqueue_all(moves)
		await cube.idle
		_silent = false
		ui.update_net(cube.model.codes)
		_refresh_coach(false)
	_auto = false
	cube.input_enabled = true
	cube.speed = saved_speed
	ui.set_auto_running(false)
	if CubeModel.is_solved(cube.model.codes):
		ui.show_toast("自动复原完成 🎉", 2.4)


func _on_stop() -> void:
	_stop_auto()
	ui.show_toast("已停止", 1.2)


func _on_reset_cube() -> void:
	_stop_auto()
	_guide_moves.clear()
	cube.reset_to_solved()
	_reset_counters()
	_armed = false
	ui.update_net(cube.model.codes)
	ui.show_toast("已重置为复原状态", 1.6)
	_refresh_coach(false)


func _stop_auto() -> void:
	var was := _auto
	_auto = false
	cube.input_enabled = true
	cube.clear_queue()
	if was and ui != null:
		ui.set_auto_running(false)


# ================================================================= 课程
func _load_lesson(index: int) -> void:
	if _lessons.is_empty():
		return
	_lesson_index = clampi(index, 0, _lessons.size() - 1)
	ui.set_lesson_index(_lesson_index)
	var lesson: Dictionary = _lessons[_lesson_index]
	ui.set_lesson(String(lesson["title"]), String(lesson["body"]))
	_stop_auto()
	_guide_moves.clear()

	var mode := String(lesson["setup_mode"])
	cube.reset_to_solved() # 每课都从复原状态开始布置局面
	match mode:
		"random":
			var n := 12
			if String(lesson["setup"]) != "":
				n = int(lesson["setup"])
			cube.apply_instant(CubeModel.random_scramble(n))
			_reset_counters()
		"inverse":
			cube.apply_instant(CubeModel.parse_sequence(CubeModel.invert_sequence(String(lesson["setup"]))))
			_reset_counters()
			_armed = false
		"moves":
			cube.apply_instant(CubeModel.parse_sequence(String(lesson["setup"])))
			_reset_counters()
			_armed = false
		_:
			pass
	_current_demo = CubeModel.parse_sequence(String(lesson["demo"]))
	ui.update_net(cube.model.codes)
	_refresh_coach(false)
	if mode == "random":
		ui.show_toast("已按本课需要打乱局面", 1.8)
