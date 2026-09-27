class_name CubeNet
extends Control

## 魔方“展开图”小面板：把当前状态画成 2D 平面图，方便教学时观察配色。
## 会根据控件大小自动缩放，窗口变大时图案也会跟着变大。

const GAP := 2.0

var codes := PackedByteArray()


func set_state(state: PackedByteArray) -> void:
	codes = state.duplicate()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	CubeModel.ensure()
	if codes.size() != 8:
		return
	var inv := CubeModel.pos_to_cubie(codes)
	# 十字展开图：上行 U，中行 L F R B，下行 D
	# 每项：[面法线, 图上向右对应方向, 图上向上对应方向, 列, 行]
	var faces := [
		[Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), 1, 0],
		[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), 0, 1],
		[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0), 1, 1],
		[Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 1, 0), 2, 1],
		[Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), 3, 1],
		[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), 1, 2],
	]
	# 整个展开图是 8 列 × 6 行的小格，按控件大小自动缩放
	var cols := 8.0
	var rows := 6.0
	var cell := minf(
		(size.x - GAP * (cols + 1.0)) / cols,
		(size.y - GAP * (rows + 1.0)) / rows
	)
	cell = maxf(cell, 6.0)
	var board_w := cols * cell + (cols + 1.0) * GAP
	var board_h := rows * cell + (rows + 1.0) * GAP
	var ox := (size.x - board_w) * 0.5
	var oy := (size.y - board_h) * 0.5

	for f: Array in faces:
		var n: Vector3i = f[0]
		var r: Vector3i = f[1]
		var u: Vector3i = f[2]
		var col: int = f[3]
		var row: int = f[4]
		for j in 2:
			for i in 2:
				var sx := i * 2 - 1
				var sy := 1 - j * 2
				var pos := Vector3i(
					n.x + r.x * sx + u.x * sy,
					n.y + r.y * sx + u.y * sy,
					n.z + r.z * sx + u.z * sy
				)
				var cid: int = inv[int(CubeModel.POS_INDEX[pos])]
				var color := CubeModel.sticker_color(codes, cid, n)
				var rect := Rect2(
					ox + (col * 2 + i) * (cell + GAP) + GAP,
					oy + (row * 2 + j) * (cell + GAP) + GAP,
					cell, cell
				)
				draw_rect(rect, color)
				draw_rect(rect, Color(0, 0, 0, 0.35), false, 1.5)
