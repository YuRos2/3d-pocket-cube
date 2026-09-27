class_name CubeView
extends Node3D

## 3D 魔方：渲染 + 转动动画 + 鼠标/触摸交互
##
## 逻辑状态始终保存在 model（CubeModel）里，画面只是它的“投影”。
## 转动动画结束后会按照 model 精确地重新摆放 8 个角块，避免浮点误差累积。

signal move_done(mi: int)   ## 一个转动播放完毕
signal idle                 ## 队列清空

const CUBIE_SIZE := 0.98
const SPACING := 0.5
const STICKER_SIZE := 0.82
const STICKER_OFFSET := CUBIE_SIZE * 0.5 + 0.006
const DRAG_THRESHOLD := 10.0

var model := CubeModel.new()
var camera: Camera3D = null
var rig: Node3D = null
var speed := 1.6            ## 动画速度倍率
var input_enabled := true

var _cubies: Array[Node3D] = []
var _queue: Array[int] = []
var _busy := false
var _working := false
var _duration := 0.18

# --- 输入状态 ---
var _press_pos := Vector2.ZERO
var _press_hit := {}
var _pressing := false
var _turn_locked := false
var _orbiting := false


func _ready() -> void:
	_build()
	_sync()


# ================================================================= 构建
func _build() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.075, 0.082, 0.10)
	body_mat.roughness = 0.55
	body_mat.metallic = 0.15

	var box := BoxMesh.new()
	box.size = Vector3.ONE * CUBIE_SIZE
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * STICKER_SIZE

	var sticker_mats: Array[StandardMaterial3D] = []
	for c: Color in CubeModel.DIR_COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.28
		m.metallic = 0.05
		m.clearcoat_enabled = true
		m.clearcoat = 0.8
		m.clearcoat_roughness = 0.08
		sticker_mats.append(m)

	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * CUBIE_SIZE

	for id in 8:
		var cubie := Node3D.new()
		cubie.name = "Cubie%d" % id
		cubie.set_meta("id", id)

		var body := MeshInstance3D.new()
		body.mesh = box
		body.material_override = body_mat
		cubie.add_child(body)

		var home := CubeModel.HOME[id]
		for di in CubeModel.DIRS.size():
			var d: Vector3i = CubeModel.DIRS[di]
			if home.x * d.x + home.y * d.y + home.z * d.z <= 0:
				continue
			var st := MeshInstance3D.new()
			st.mesh = quad
			st.material_override = sticker_mats[di]
			st.transform = _sticker_transform(d)
			cubie.add_child(st)

		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		sb.add_child(cs)
		cubie.add_child(sb)

		add_child(cubie)
		_cubies.append(cubie)


static func _sticker_transform(d: Vector3i) -> Transform3D:
	var b: Basis
	if d == Vector3i(0, 0, 1):
		b = Basis()
	elif d == Vector3i(0, 0, -1):
		b = Basis(Vector3.UP, PI)
	elif d == Vector3i(1, 0, 0):
		b = Basis(Vector3.UP, PI * 0.5)
	elif d == Vector3i(-1, 0, 0):
		b = Basis(Vector3.UP, -PI * 0.5)
	elif d == Vector3i(0, 1, 0):
		b = Basis(Vector3.RIGHT, -PI * 0.5)
	else:
		b = Basis(Vector3.RIGHT, PI * 0.5)
	return Transform3D(b, Vector3(d) * STICKER_OFFSET)


## 用 model 的状态精确摆放 8 个角块
func _sync() -> void:
	for id in 8:
		var code: int = model.codes[id]
		var pos := CubeModel.pos_of(code)
		var b: Basis = CubeModel.CODE_BASIS[id][code]
		_cubies[id].transform = Transform3D(b, Vector3(pos) * SPACING)


# ================================================================= 转动
func is_busy() -> bool:
	return _busy or not _queue.is_empty()


func enqueue(mi: int) -> void:
	_queue.append(mi)
	_try_next()


func enqueue_all(moves: Array) -> void:
	for mi in moves:
		_queue.append(int(mi))
	_try_next()


func clear_queue() -> void:
	_queue.clear()


## 立刻应用一串转动（用于打乱 / 布置教学局面）
func apply_instant(moves: Array) -> void:
	clear_queue()
	CubeModel.apply_sequence(model.codes, moves)
	_sync()
	pulse()


## 回到已复原状态
func reset_to_solved() -> void:
	clear_queue()
	model.reset()
	_sync()


func pulse() -> void:
	var t := create_tween()
	scale = Vector3.ONE * 0.94
	t.tween_property(self, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _try_next() -> void:
	if _busy:
		return
	if _queue.is_empty():
		if _working:
			_working = false
			idle.emit()
		return
	_busy = true
	_working = true
	_start(_queue.pop_front())


func _start(mi: int) -> void:
	var m: Dictionary = CubeModel.MOVES[mi]
	var axis_i: Vector3i = m["axis_i"]
	var layer: int = m["layer"]
	var quarter: int = m["quarter"]

	var moving: Array[Node3D] = []
	for id in 8:
		var p := CubeModel.pos_of(model.codes[id])
		if axis_i.x * p.x + axis_i.y * p.y + axis_i.z * p.z == layer:
			moving.append(_cubies[id])

	var pivot := Node3D.new()
	add_child(pivot)
	for c: Node3D in moving:
		c.reparent(pivot, true)

	var target := Vector3.ZERO
	target[int(m["axis_index"])] = quarter * PI * 0.5
	_duration = 0.26 / maxf(speed, 0.15)
	if _duration < 0.05:
		_duration = 0.05

	var t := create_tween()
	t.set_trans(Tween.TRANS_CUBIC)
	t.set_ease(Tween.EASE_OUT if speed >= 2.0 else Tween.EASE_IN_OUT)
	t.tween_property(pivot, "rotation", target, _duration)
	t.tween_callback(_finish.bind(pivot, moving, mi))


func _finish(pivot: Node3D, moving: Array, mi: int) -> void:
	CubeModel.apply_move_to(model.codes, mi)
	for c: Node3D in moving:
		c.reparent(self, true)
	_sync()
	pivot.queue_free()
	_busy = false
	move_done.emit(mi)
	_try_next()


# ================================================================= 视角与交互
func reset_view() -> void:
	if rig == null:
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(rig, "rotation", Vector3(deg_to_rad(-24), deg_to_rad(32), 0), 0.35)
	if camera != null:
		t.tween_property(camera, "position", Vector3(0, 0, 5.6), 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or camera == null or rig == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(-0.45)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(0.45)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_begin_press(mb.position)
				else:
					_end_press()
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_orbiting = true
				else:
					_orbiting = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_orbit(mm.relative)
		elif _pressing:
			_update_press(mm.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_begin_press(st.position)
		else:
			_end_press()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _pressing:
			_update_press(sd.position)


func _zoom(delta: float) -> void:
	camera.position.z = clampf(camera.position.z + delta, 3.0, 13.0)


func _orbit(rel: Vector2) -> void:
	rig.rotation.y -= rel.x * 0.008
	rig.rotation.x = clampf(rig.rotation.x - rel.y * 0.008, -1.35, 1.35)


func _raycast(screen_pos: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0, 1)
	return get_world_3d().direct_space_state.intersect_ray(params)


func _begin_press(pos: Vector2) -> void:
	if is_busy():
		# 动画中仍然允许旋转视角
		_orbiting = true
		return
	var hit := _raycast(pos)
	if hit.is_empty():
		_orbiting = true
		return
	_pressing = true
	_turn_locked = false
	_press_pos = pos
	_press_hit = hit


func _end_press() -> void:
	_pressing = false
	_turn_locked = false
	_orbiting = false


func _update_press(pos: Vector2) -> void:
	if _turn_locked:
		return
	var d := pos - _press_pos
	if d.length() < DRAG_THRESHOLD:
		return
	_turn_locked = true
	_do_turn(d)


## 根据“按下的面 + 拖动方向”推断要转动哪一层（返回转动索引，无法判断时返回 -1）
func _resolve_move(
	world_normal: Vector3,
	world_pos: Vector3,
	local_center: Vector3,
	drag: Vector2
) -> int:
	# 该面所在的两个切线方向中，屏幕投影与拖动方向最接近的那个
	var dn := drag.normalized()
	var best := Vector3.ZERO
	var best_dot := -2.0
	for a: Vector3 in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
		if absf(a.dot(world_normal)) > 0.5:
			continue
		for s: float in [1.0, -1.0]:
			var t := a * s
			var p0 := camera.unproject_position(world_pos)
			var p1 := camera.unproject_position(world_pos + t * 0.35)
			var sd := p1 - p0
			if sd.length() < 0.5:
				continue
			var dot := dn.dot(sd.normalized())
			if dot > best_dot:
				best_dot = dot
				best = t
	if best == Vector3.ZERO:
		return -1

	var axis: Vector3 = world_normal.cross(best).snapped(Vector3.ONE)
	var layer_sign := signi(roundi(axis.dot(local_center)))
	var quarter := 1
	if axis.x + axis.y + axis.z < 0.0:
		axis = -axis
		quarter = -1
		layer_sign = -layer_sign
	var axis_i := Vector3i(roundi(axis.x), roundi(axis.y), roundi(axis.z))
	return CubeModel.find_move(axis_i, layer_sign, quarter)


## 根据“按下的面 + 拖动方向”推断要转动哪一层
func _do_turn(drag: Vector2) -> void:
	var world_normal: Vector3 = (_press_hit["normal"] as Vector3).snapped(Vector3.ONE)
	var world_pos: Vector3 = _press_hit["position"]
	var collider: Object = _press_hit["collider"]
	var body := collider as Node
	if body == null:
		return
	var cubie := body.get_parent() as Node3D
	var local_center := to_local(cubie.global_position) * (1.0 / SPACING)
	var mi := _resolve_move(world_normal, world_pos, local_center, drag)
	if mi >= 0:
		enqueue(mi)
