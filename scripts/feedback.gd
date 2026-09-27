class_name Feedback
extends Node

## 声音反馈：用代码合成短音，不依赖任何外部音频文件。
## 小朋友对“转动的咔哒声”和“复原成功的音乐”反应很好，同时保留一键静音。

var enabled := true

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _cache := {}


func _ready() -> void:
	for i in 5:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		p.volume_db = -4.0
		add_child(p)
		_players.append(p)


func set_enabled(on: bool) -> void:
	enabled = on


## 合成一段音符序列（每项为 [频率, 时长]）
func _synth(key: String, notes: Array, vol: float, rate: int = 22050) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var data := PackedByteArray()
	for n: Array in notes:
		var freq: float = float(n[0])
		var dur: float = float(n[1])
		var count: int = maxi(1, int(rate * dur))
		var start := data.size()
		data.resize(start + count * 2)
		var fade := 0.012
		for i in count:
			var t := float(i) / float(rate)
			var env := 1.0
			if t < fade:
				env = t / fade
			elif dur - t < fade:
				env = maxf(0.0, (dur - t) / fade)
			var s := sin(TAU * freq * t)
			s += sin(TAU * freq * 2.0 * t) * 0.18  # 一点泛音，声音更圆润
			s = clampf(s * env * vol, -1.0, 1.0)
			data.encode_s16(start + i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	_cache[key] = wav
	return wav


func _play(key: String, notes: Array, vol: float) -> void:
	if not enabled or _players.is_empty() or not is_inside_tree():
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _synth(key, notes, vol)
	p.play()


func play_turn() -> void:
	_play("turn", [[720.0, 0.05]], 0.22)


func play_undo() -> void:
	_play("undo", [[430.0, 0.06]], 0.20)


func play_click() -> void:
	_play("click", [[920.0, 0.04]], 0.16)


func play_success() -> void:
	_play("success", [[784.0, 0.11], [988.0, 0.11], [1319.0, 0.26]], 0.24)
