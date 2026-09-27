class_name GameUI
extends CanvasLayer

## 全部 UI（顶栏 + 左侧教学面板 + 展开图 + 提示条 + 撒花），使用代码构建。
## 面向中小学生：明亮配色、大字号、大按钮、步骤引导和“下一步”提示。
## 通过信号把玩家操作告诉 main.gd。

signal scramble_requested
signal undo_requested
signal hint_requested
signal solve_requested
signal stop_requested
signal reset_requested
signal view_reset_requested
signal lesson_changed(index: int)
signal demo_requested
signal step_requested
signal speed_changed(value: float)
signal sound_toggled(on: bool)

const INK := Color(0.12, 0.15, 0.26)
const INK_SOFT := Color(0.40, 0.45, 0.58)
const ACCENT := Color(0.95, 0.47, 0.08)
const BLUE := Color(0.16, 0.45, 0.93)
const GREEN := Color(0.10, 0.62, 0.34)
const STEP_NAMES := ["① 白面", "② 黄面", "③ 归位"]

var _root: Control
var _panel: PanelContainer
var _picker: OptionButton
var _lesson_title: Label
var _lesson_body: RichTextLabel
var _coach: RichTextLabel
var _progress: Label
var _next_label: Label
var _step_button: Button
var _demo_button: Button
var _timer_label: Label
var _moves_label: Label
var _history_label: Label
var _record_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _net: CubeNet
var _toast_tween: Tween
var _toggle_button: Button
var _solve_button: Button
var _sound_button: Button
var _step_chips: Array[PanelContainer] = []
var _step_texts: Array[Label] = []
var _auto_running := false
var _sound_on := true


func _ready() -> void:
	_root = Control.new()
	_root.name = "UIRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_top_bar()
	_build_panel()
	_build_toast()


# ================================================================= 主题
func _make_theme() -> Theme:
	var th := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
		"Source Han Sans SC", "PingFang SC", "sans-serif",
	])
	f.allow_system_fallback = true
	th.default_font = f
	th.default_font_size = 18

	# —— 面板：明亮的浅色卡片 ——
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.98, 0.98, 1.0, 0.97)
	panel.set_corner_radius_all(16)
	panel.set_border_width_all(2)
	panel.border_color = Color(0.74, 0.80, 0.96)
	panel.set_content_margin_all(14)
	th.set_stylebox("panel", "PanelContainer", panel)

	# —— 按钮：大圆角、浅底深字 ——
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.90, 0.93, 1.0)
	btn.set_corner_radius_all(12)
	btn.set_border_width_all(2)
	btn.border_color = Color(0.76, 0.82, 0.98)
	btn.set_content_margin_all(9)
	btn.content_margin_left = 16
	btn.content_margin_right = 16
	th.set_stylebox("normal", "Button", btn)

	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.82, 0.88, 1.0)
	th.set_stylebox("hover", "Button", btn_hover)

	var btn_press := btn.duplicate() as StyleBoxFlat
	btn_press.bg_color = Color(0.68, 0.80, 1.0)
	th.set_stylebox("pressed", "Button", btn_press)

	var btn_dis := btn.duplicate() as StyleBoxFlat
	btn_dis.bg_color = Color(0.88, 0.89, 0.92, 0.8)
	btn_dis.border_color = Color(0.82, 0.83, 0.86, 0.8)
	th.set_stylebox("disabled", "Button", btn_dis)

	th.set_color("font_color", "Button", INK)
	th.set_color("font_hover_color", "Button", INK)
	th.set_color("font_pressed_color", "Button", Color(0.05, 0.18, 0.45))
	th.set_color("font_disabled_color", "Button", Color(0.62, 0.65, 0.72))
	th.set_font_size("font_size", "Button", 18)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	th.set_color("font_color", "Label", INK)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_font_size("normal_font_size", "RichTextLabel", 17)
	th.set_font_size("bold_font_size", "RichTextLabel", 17)

	# —— 滑块 ——
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.84, 0.87, 0.95)
	slider_bg.set_corner_radius_all(5)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", slider_bg)
	var slider_fg := slider_bg.duplicate() as StyleBoxFlat
	slider_fg.bg_color = BLUE
	th.set_stylebox("grabber_area", "HSlider", slider_fg)
	th.set_stylebox("grabber_area_highlight", "HSlider", slider_fg)

	# —— 下拉框 ——
	th.set_color("font_color", "OptionButton", INK)
	th.set_font_size("font_size", "OptionButton", 17)
	th.set_stylebox("normal", "OptionButton", btn)
	th.set_stylebox("hover", "OptionButton", btn_hover)
	th.set_stylebox("pressed", "OptionButton", btn_press)
	th.set_stylebox("disabled", "OptionButton", btn_dis)
	th.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())

	var pop := StyleBoxFlat.new()
	pop.bg_color = Color(0.99, 0.99, 1.0, 1.0)
	pop.set_corner_radius_all(10)
	pop.set_border_width_all(2)
	pop.border_color = Color(0.74, 0.80, 0.96)
	pop.set_content_margin_all(6)
	th.set_stylebox("panel", "PopupMenu", pop)
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", Color(0.05, 0.18, 0.45))
	th.set_font_size("font_size", "PopupMenu", 17)
	var pop_hover := StyleBoxFlat.new()
	pop_hover.bg_color = Color(0.84, 0.90, 1.0)
	pop_hover.set_corner_radius_all(6)
	pop_hover.set_content_margin_all(6)
	th.set_stylebox("hover", "PopupMenu", pop_hover)
	return th


func _label(text: String, size: int = 18, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _button(text: String, tip: String = "", size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", size)
	return b


## 给按钮换成“彩色实心”样式（用于主要操作）
func _tint(b: Button, base: Color) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = base
	n.set_corner_radius_all(12)
	n.set_border_width_all(2)
	n.border_color = base.lightened(0.28)
	n.set_content_margin_all(9)
	n.content_margin_left = 16
	n.content_margin_right = 16
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = base.lightened(0.14)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = base.darkened(0.18)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, Color(1, 1, 1))


func _rich(size: int = 17) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size + 1)
	return r


func _card(parent: Node, bg: Color, border: Color, pad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


# ================================================================= 顶栏
func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 66
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bar)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	bar.add_child(hb)

	var title := _label("🧩 魔方乐园", 21, ACCENT)
	hb.add_child(title)

	_timer_label = _label("00:00.00", 19, INK)
	_timer_label.custom_minimum_size = Vector2(98, 0)
	hb.add_child(_timer_label)
	_moves_label = _label("步数 0", 16, INK_SOFT)
	hb.add_child(_moves_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	var b_scramble := _button("🎲 打乱", "随机打乱魔方（空格）", 17)
	_tint(b_scramble, ACCENT)
	b_scramble.pressed.connect(func() -> void: scramble_requested.emit())
	hb.add_child(b_scramble)

	var b_hint := _button("💡 提示", "分析当前局面并给出下一步建议（H）", 17)
	_tint(b_hint, BLUE)
	b_hint.pressed.connect(func() -> void: hint_requested.emit())
	hb.add_child(b_hint)

	var b_demo := _button("🎬 演示", "把当前这一步完整演示一遍", 17)
	b_demo.pressed.connect(func() -> void: demo_requested.emit())
	hb.add_child(b_demo)

	_solve_button = _button("🪄 自动复原", "让电脑按“层先法”自动复原（S）", 17)
	_tint(_solve_button, GREEN)
	_solve_button.pressed.connect(_on_solve_or_stop)
	hb.add_child(_solve_button)

	var b_reset := _button("↺ 重置", "立刻回到已复原状态", 17)
	b_reset.pressed.connect(func() -> void: reset_requested.emit())
	hb.add_child(b_reset)

	var b_view := _button("🔄 视角", "恢复默认视角（V）", 17)
	b_view.pressed.connect(func() -> void: view_reset_requested.emit())
	hb.add_child(b_view)

	var b_undo := _button("↩ 撤销", "撤销上一步（Z）", 17)
	b_undo.pressed.connect(func() -> void: undo_requested.emit())
	hb.add_child(b_undo)

	_sound_button = _button("🔊", "打开 / 关闭音效", 19)
	_sound_button.custom_minimum_size = Vector2(46, 0)
	_sound_button.pressed.connect(_on_sound_pressed)
	hb.add_child(_sound_button)

	_toggle_button = _button("📖 收起", "收起 / 展开教学面板（T / Esc）", 17)
	_toggle_button.pressed.connect(toggle_panel)
	hb.add_child(_toggle_button)


func _on_solve_or_stop() -> void:
	if _auto_running:
		stop_requested.emit()
	else:
		solve_requested.emit()


func _on_sound_pressed() -> void:
	_sound_on = not _sound_on
	_sound_button.text = "🔊" if _sound_on else "🔇"
	sound_toggled.emit(_sound_on)


# ================================================================= 教学面板
func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 12
	_panel.offset_right = 388
	_panel.offset_top = 78
	_panel.offset_bottom = -12
	_root.add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)

	# 课程选择
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	head.add_child(_label("📚 课程", 18, INK))
	_picker = OptionButton.new()
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(func(i: int) -> void: lesson_changed.emit(i))
	head.add_child(_picker)

	_lesson_title = _label("", 21, ACCENT)
	_lesson_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_lesson_title)

	_lesson_body = _rich(17)
	vb.add_child(_lesson_body)

	# 三步进度
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	vb.add_child(steps)
	for i in STEP_NAMES.size():
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lab := _label(STEP_NAMES[i], 16, INK_SOFT)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_child(lab)
		steps.add_child(chip)
		_step_chips.append(chip)
		_step_texts.append(lab)

	# 教练提示
	var coach_card := _card(vb, Color(1.0, 0.97, 0.86), Color(0.96, 0.80, 0.35), 10)
	var coach_vb := VBoxContainer.new()
	coach_vb.add_theme_constant_override("separation", 4)
	coach_card.add_child(coach_vb)
	coach_vb.add_child(_label("🐻 教练说", 17, Color(0.72, 0.42, 0.02)))
	_coach = _rich(17)
	coach_vb.add_child(_coach)

	_progress = _label("", 16, BLUE)
	vb.add_child(_progress)

	# 下一步提示（固定在底部，永远看得见）
	var next_card := _card(outer, Color(0.88, 0.94, 1.0), Color(0.55, 0.72, 0.98), 10)
	var next_row := HBoxContainer.new()
	next_row.add_theme_constant_override("separation", 8)
	next_card.add_child(next_row)
	_next_label = _label("下一步：准备好了吗？", 19, INK)
	_next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_row.add_child(_next_label)
	_step_button = _button("▶ 走一步", "帮你转动下一步")
	_tint(_step_button, BLUE)
	_step_button.pressed.connect(func() -> void: step_requested.emit())
	next_row.add_child(_step_button)

	# 操作按钮
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	vb.add_child(row1)
	_demo_button = _button("🎬 帮我做完这一步", "把当前这一阶段自动转完")
	_demo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_demo_button.pressed.connect(func() -> void: demo_requested.emit())
	row1.add_child(_demo_button)
	var b_re := _button("🔄 重新分析", "重新分析当前局面")
	b_re.pressed.connect(func() -> void: hint_requested.emit())
	row1.add_child(b_re)

	# 上一课 / 下一课
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	vb.add_child(row2)
	var b_prev := _button("◀ 上一课", "", 17)
	b_prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_prev.pressed.connect(func() -> void: lesson_changed.emit(maxi(0, _picker.selected - 1)))
	row2.add_child(b_prev)
	var b_next := _button("下一课 ▶", "", 17)
	b_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_next.pressed.connect(func() -> void:
		lesson_changed.emit(mini(_picker.item_count - 1, _picker.selected + 1)))
	row2.add_child(b_next)

	# 展开图（固定在面板底部，随时都能看到）
	var net_head := HBoxContainer.new()
	net_head.add_theme_constant_override("separation", 8)
	outer.add_child(net_head)
	net_head.add_child(_label("🧭 展开图", 17, INK))
	_history_label = _label("", 14, INK_SOFT)
	_history_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	net_head.add_child(_history_label)

	_net = CubeNet.new()
	_net.custom_minimum_size = Vector2(0, 118)
	_net.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_net)

	_record_label = _label("🏆 还没有记录，快来挑战！", 16, Color(0.72, 0.42, 0.02))
	outer.add_child(_record_label)

	# 转动速度
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	outer.add_child(speed_row)
	speed_row.add_child(_label("转动速度", 16, INK_SOFT))
	var slider := HSlider.new()
	slider.min_value = 0.6
	slider.max_value = 3.0
	slider.step = 0.1
	slider.value = 1.6
	slider.custom_minimum_size = Vector2(0, 26)
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "转动动画速度"
	slider.value_changed.connect(func(v: float) -> void: speed_changed.emit(v))
	speed_row.add_child(slider)


# ================================================================= 提示条
func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -260
	_toast.offset_right = 260
	_toast.offset_top = -118
	_toast.offset_bottom = -54
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_root.add_child(_toast)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.55, 0.34, 0.96)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.6, 1.0, 0.75, 0.55)
	sb.set_content_margin_all(12)
	_toast.add_theme_stylebox_override("panel", sb)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.add_theme_font_size_override("font_size", 19)
	_toast_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast.add_child(_toast_label)


# ================================================================= 对外接口
func set_lessons(titles: Array) -> void:
	_picker.clear()
	for i in titles.size():
		_picker.add_item(str(titles[i]), i)


func set_lesson_index(i: int) -> void:
	_picker.select(clampi(i, 0, maxi(0, _picker.item_count - 1)))


func set_lesson(title: String, body: String) -> void:
	_lesson_title.text = title
	_lesson_body.text = body


func set_coach(text: String, has_demo: bool) -> void:
	_coach.text = text
	_demo_button.disabled = not has_demo


func set_progress(text: String) -> void:
	_progress.text = text


## phase：0=白面 1=黄面 2=归位 3=全部完成
func set_steps(phase: int) -> void:
	for i in _step_chips.size():
		var done := i < phase
		var current := i == phase
		var bg := Color(0.90, 0.92, 0.97)
		var bd := Color(0.80, 0.84, 0.93)
		var fg := INK_SOFT
		if done:
			bg = Color(0.84, 0.95, 0.86)
			bd = GREEN
			fg = Color(0.06, 0.42, 0.22)
		elif current:
			bg = Color(0.85, 0.91, 1.0)
			bd = BLUE
			fg = Color(0.08, 0.28, 0.72)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = bd
		sb.set_content_margin_all(6)
		_step_chips[i].add_theme_stylebox_override("panel", sb)
		_step_texts[i].add_theme_color_override("font_color", fg)
		var mark := "✅ " if done else ("👉 " if current else "◻ ")
		_step_texts[i].text = mark + String(STEP_NAMES[i])


func set_next_move(text: String, enabled: bool) -> void:
	_next_label.text = text
	_step_button.disabled = not enabled


func set_record(text: String) -> void:
	_record_label.text = text


func set_moves(n: int) -> void:
	_moves_label.text = "步数 %d" % n


func set_timer(text: String) -> void:
	_timer_label.text = text


func set_history(text: String) -> void:
	_history_label.text = text


func set_auto_running(running: bool) -> void:
	_auto_running = running
	if _solve_button == null:
		return
	_solve_button.text = "⏹ 停止" if running else "🤖 自动复原"
	if running:
		_tint(_solve_button, Color(0.85, 0.24, 0.24))
	else:
		_tint(_solve_button, GREEN)


func update_net(state: PackedByteArray) -> void:
	_net.set_state(state)


func show_toast(text: String, seconds: float = 2.6) -> void:
	_toast_label.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.45)


## 复原成功时的撒花庆祝
func celebrate(text: String) -> void:
	if _root == null:
		return
	var center := _root.size * 0.5
	if center == Vector2.ZERO:
		center = Vector2(640, 380)

	var big := Label.new()
	big.text = text
	big.add_theme_font_size_override("font_size", 46)
	big.add_theme_color_override("font_color", Color(1.0, 0.84, 0.16))
	big.add_theme_color_override("font_outline_color", Color(0.32, 0.16, 0.0))
	big.add_theme_constant_override("outline_size", 8)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.size = Vector2(640, 100)
	big.position = center - Vector2(320, 50)
	big.pivot_offset = Vector2(320, 50)
	big.scale = Vector2(0.4, 0.4)
	big.modulate.a = 0.0
	_root.add_child(big)
	var t := create_tween().set_parallel(true)
	t.tween_property(big, "modulate:a", 1.0, 0.18)
	t.tween_property(big, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var t2 := create_tween()
	t2.tween_interval(1.7)
	t2.set_parallel(true)
	t2.tween_property(big, "modulate:a", 0.0, 0.5)
	t2.tween_property(big, "scale", Vector2(1.3, 1.3), 0.5)
	t2.chain().tween_callback(big.queue_free)

	var emojis := ["🎉", "⭐", "✨", "🎈", "🌟", "💛", "🧡", "💙", "🥳"]
	for i in 22:
		var e := Label.new()
		e.text = emojis[i % emojis.size()]
		e.add_theme_font_size_override("font_size", 26 + (i % 4) * 8)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		e.position = center - Vector2(18, 18)
		_root.add_child(e)
		var ang := randf() * TAU
		var dist := 150.0 + randf() * 300.0
		var dest := Vector2(cos(ang), sin(ang) - 0.35) * dist
		var et := create_tween().set_parallel(true)
		et.tween_property(e, "position", e.position + dest, 0.9 + randf() * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		et.tween_property(e, "rotation", randf_range(-1.4, 1.4), 1.1)
		et.tween_property(e, "modulate:a", 0.0, 0.8).set_delay(0.45)
		et.chain().tween_callback(e.queue_free)


func is_panel_visible() -> bool:
	return _panel.visible


func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	_update_toggle_text()


func _update_toggle_text() -> void:
	if _toggle_button != null:
		_toggle_button.text = "📖 收起" if _panel.visible else "📖 教学"
