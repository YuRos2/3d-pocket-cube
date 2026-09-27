extends Node

## 画面自检：渲染一帧并统计像素，确认魔方贴纸颜色、位置和 UI 文字都正常绘制。
## 运行：godot --path . res://tests/visual_check.tscn

const SHOT := "user://pocketcube_shot.png"
const CUBE_X0 := 400
const CUBE_Y0 := 70
const PANEL_X1 := 388

var _fails := 0


func _ready() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for i in 25:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT)
	_analyze(img)
	print("VISUAL: %s（失败 %d）" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("  [FAIL] ", msg)


func _analyze(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var targets := {
		"黄U": Color(0.98, 0.82, 0.15),
		"绿F": Color(0.20, 0.72, 0.32),
		"红R": Color(0.85, 0.20, 0.18),
		"橙L": Color(1.00, 0.53, 0.12),
		"蓝B": Color(0.16, 0.42, 0.88),
	}
	var counts := {}
	for k: String in targets:
		counts[k] = 0

	# —— 第一遍：找魔方上的彩色贴纸，得到包围盒 ——
	var box := [99999, 99999, -1, -1]
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if x <= CUBE_X0 or y <= CUBE_Y0:
				continue
			var c := img.get_pixel(x, y)
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			if mx > 0.35 and (mx - mn) > 0.20:
				var best := ""
				var best_d := 9.0
				for k: String in targets:
					var t: Color = targets[k]
					var d := absf(c.r - t.r) + absf(c.g - t.g) + absf(c.b - t.b)
					if d < best_d:
						best_d = d
						best = k
				if best != "" and best_d < 0.55:
					counts[best] = int(counts[best]) + 1
					box[0] = mini(box[0], x); box[1] = mini(box[1], y)
					box[2] = maxi(box[2], x); box[3] = maxi(box[3], y)

	# —— 第二遍：在魔方范围内统计“近白色”像素（底面白色贴纸不应露出）——
	var white := 0
	if box[2] > box[0]:
		for y in range(box[1] + 8, box[3] - 7, 2):
			for x in range(box[0] + 8, box[2] - 7, 2):
				var c := img.get_pixel(x, y)
				var mx := maxf(c.r, maxf(c.g, c.b))
				var mn := minf(c.r, minf(c.g, c.b))
				if mx > 0.85 and (mx - mn) < 0.05:
					white += 1

	# —— 第三遍：UI 文字与展开图 ——
	var panel_text := 0
	var topbar_text := 0
	var panel_colors := {}
	for k: String in targets:
		panel_colors[k] = 0
	var dark := 0
	var samples := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			samples += 1
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b < 0.22:
				dark += 1
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			# 浅色面板上的深色文字
			if x < PANEL_X1 and y > 78 and mx < 0.45 and (mx - mn) < 0.25:
				panel_text += 1
			# 展开图上的贴纸颜色
			if x < PANEL_X1 and y > 78 and mx > 0.35 and (mx - mn) > 0.20:
				for k: String in targets:
					var t: Color = targets[k]
					if absf(c.r - t.r) + absf(c.g - t.g) + absf(c.b - t.b) < 0.30:
						panel_colors[k] = int(panel_colors[k]) + 1
						break
			# 顶栏深色文字
			if y < 66 and mx < 0.5:
				topbar_text += 1

	print("分辨率 %dx%d，采样 %d 点" % [w, h, samples])
	print("贴纸像素：", counts, " 白色=", white)
	print("贴纸包围盒：x %d..%d  y %d..%d" % [box[0], box[2], box[1], box[3]])
	print("UI 文字像素：面板=%d 顶栏=%d   深色像素=%d" % [panel_text, topbar_text, dark])
	print("面板内贴纸颜色（展开图）：", panel_colors)

	_check(int(counts["黄U"]) > 200, "顶面黄色可见")
	_check(int(counts["绿F"]) > 200, "前面绿色可见")
	_check(int(counts["红R"]) > 200, "右面红色可见")
	_check(int(counts["橙L"]) + int(counts["蓝B"]) < 400, "背面颜色几乎不可见")
	_check(white < 300, "底面白色不可见（相机在上方）")
	# 展开图应当六色俱全
	for k: String in panel_colors:
		_check(int(panel_colors[k]) > 20, "展开图绘出了 %s 色（%d）" % [k, panel_colors[k]])
	_check(box[0] > PANEL_X1, "魔方没有被左侧面板遮住")
	_check(box[2] - box[0] > 200, "魔方在画面中有足够大小（宽 %d）" % (box[2] - box[0]))
	_check(box[1] > CUBE_Y0, "魔方没有被顶栏遮住")
	_check(panel_text > 300, "教学面板文字已绘制（%d）" % panel_text)
	_check(topbar_text > 150, "顶栏文字已绘制（%d）" % topbar_text)
	_check(dark * 100 / samples < 92, "画面不是全黑")
