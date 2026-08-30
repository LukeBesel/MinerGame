## Juice — screen-space game feel: squash, floating text, coin bursts, count-ups,
## camera shake, slow-mo, and the bottleneck-cleared flash. Autoload owning a layer-90
## CanvasLayer. Every effect honors reduce_motion / screen_shake (read defensively —
## the save module is built in parallel) and survives freed cameras/labels.
extends Node

const BigNum = preload("res://src/sim/big_num.gd")

const LAYER_INDEX := 90
const FLOAT_CAP := 30
const FLOAT_RISE_PX := 50.0
const FLOAT_LIFETIME := 0.9
const SHAKE_DURATION := 0.3
const SHAKE_MAX_OFFSET := 0.35			# meters of camera offset at strength 1, shake setting 1
const BURST_THROTTLE_MS := 150
const UPGRADE_FX_WINDOW_MS := 1500
const AMBER := Color("F4B942")
const GREEN := Color("3FA34D")
const FLASH_COLOR := Color(0.25, 0.64, 0.3, 0.18)

var _canvas: CanvasLayer = null
var _flash_rect: TextureRect = null
var _flash_tween: Tween = null
var _particle_tex: Texture2D = null

var _float_free: Array[Label] = []
var _float_live: Array[Label] = []

var _count_tweens: Dictionary = {}		# label instance id -> Tween
var _squash_tweens: Dictionary = {}		# control instance id -> Tween
var _slowmo_tween: Tween = null

var _shake_cam: Camera3D = null
var _shake_time_left: float = 0.0
var _shake_strength: float = 0.0
var _shake_base_h: float = 0.0
var _shake_base_v: float = 0.0

var _station_tp: Dictionary = {}		# station index -> last known effective throughput
var _pending_station: int = -1
var _pending_tp_before: float = -1.0
var _pending_ms: int = 0
var _last_burst_ms: int = -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = CanvasLayer.new()
	_canvas.layer = LAYER_INDEX
	_canvas.name = "JuiceLayer"
	add_child(_canvas)
	_build_flash_rect()
	_build_particle_texture()
	EventBus.station_upgraded.connect(_on_station_upgraded)
	EventBus.bottleneck_cleared.connect(_on_bottleneck_cleared)
	EventBus.prestige_performed.connect(_on_prestige_performed)
	EventBus.milestone_reached.connect(_on_milestone_reached)
	EventBus.sim_stats.connect(_on_sim_stats)


func _exit_tree() -> void:
	Engine.time_scale = 1.0		# never leave the game slowed


## ------------------------------------------------------------------ public API

## Quick 0.92 -> 1.0 elastic scale pop on a Control (pivot centered).
func squash(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	if _reduce_motion():
		c.scale = Vector2.ONE
		return
	c.pivot_offset = c.size * 0.5
	var key := c.get_instance_id()
	_kill_tracked(_squash_tweens, key)
	c.scale = Vector2(0.92, 0.92)
	var tw := create_tween()
	tw.bind_node(c)
	tw.tween_property(c, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(_untrack.bind(_squash_tweens, key))
	_squash_tweens[key] = tw


## Rising, fading label at a screen position. Pooled; at most FLOAT_CAP live
## (the oldest gets recycled under spam). reduce_motion: fades in place instead.
func float_text(text: String, screen_pos: Vector2, color: Color) -> void:
	if _canvas == null:
		return
	var lbl := _obtain_label()
	if lbl == null:
		return
	lbl.text = text
	lbl.modulate = Color(color.r, color.g, color.b, 1.0)
	lbl.reset_size()
	var start := screen_pos - lbl.size * 0.5
	lbl.position = start
	lbl.visible = true
	var tw := create_tween()
	if _reduce_motion():
		tw.tween_interval(0.35)
		tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	else:
		var drift := randf_range(-14.0, 14.0)
		tw.set_parallel(true)
		tw.tween_property(lbl, "position", start + Vector2(drift, -FLOAT_RISE_PX), FLOAT_LIFETIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(lbl, "modulate:a", 0.0, FLOAT_LIFETIME) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(_release_label.bind(lbl))
	lbl.set_meta("juice_tween", tw)


## One-shot burst of 8-16 amber squares with a gravity arc; frees itself.
func coin_burst(screen_pos: Vector2) -> void:
	if _reduce_motion():
		return
	_spawn_burst(screen_pos, randi_range(8, 16), 1.0)


## Tween label text from -> to, calling fmt(value) each step (fmt may return the
## String to display, or set the text itself and return null). from/to may be
## float OR BigNum (duck-typed via to_float). Money glides; e >= 300 snaps.
func count_up(label: Label, from: Variant, to: Variant, fmt: Callable, duration: float = 0.35) -> void:
	if label == null or not is_instance_valid(label) or not fmt.is_valid():
		return
	var key := label.get_instance_id()
	_kill_tracked(_count_tweens, key)
	var from_big := _is_bignum(from)
	var to_big := _is_bignum(to)
	if _reduce_motion() or duration <= 0.0:
		_apply_count(label, fmt, to)
		return
	var fe := int(from.get("e")) if from_big else _float_e(from)
	var te := int(to.get("e")) if to_big else _float_e(to)
	if fe >= 300 or te >= 300:
		_apply_count(label, fmt, to)	# beyond float precision: snap, no garbage lerp
		return
	var f0 := float(from.to_float()) if from_big else float(from)
	var f1 := float(to.to_float()) if to_big else float(to)
	var tw := create_tween()
	tw.bind_node(label)
	var stepper := Callable(self, "_count_step_float")
	if from_big or to_big:
		stepper = Callable(self, "_count_step_big")
	tw.tween_method(stepper.bind(label, fmt), f0, f1, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_apply_count.bind(label, fmt, to))	# land exactly on target
	tw.finished.connect(_untrack.bind(_count_tweens, key))
	_count_tweens[key] = tw


## Decaying random jitter on the active 3D camera's h/v offsets (~0.3 s), scaled
## by SettingsService.screen_shake. No-op under reduce_motion or shake setting 0.
func shake(strength: float = 1.0) -> void:
	if _reduce_motion():
		return
	var setting := _shake_setting()
	if setting <= 0.0 or strength <= 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return
	if _shake_time_left > 0.0 and _shake_cam != cam:
		_restore_cam()	# camera changed mid-shake: put the old one back first
	if _shake_time_left <= 0.0 or _shake_cam != cam:
		_shake_cam = cam
		_shake_base_h = cam.h_offset
		_shake_base_v = cam.v_offset
	_shake_strength = maxf(_shake_strength, strength * setting)
	_shake_time_left = SHAKE_DURATION


## Engine.time_scale dip with smooth recovery. HARD no-op under reduce_motion.
## Single active handle: a second call restarts the dip and 1.0 is always restored.
func slowmo(time_scale: float = 0.35, duration: float = 0.4) -> void:
	if _reduce_motion():
		return
	if _slowmo_tween != null and _slowmo_tween.is_valid():
		_slowmo_tween.kill()
	_slowmo_tween = null
	Engine.time_scale = clampf(time_scale, 0.05, 1.0)
	var tw := create_tween()
	if tw.has_method("set_ignore_time_scale"):
		tw.set_ignore_time_scale(true)
	tw.tween_interval(maxf(duration * 0.6, 0.01))
	tw.tween_property(Engine, "time_scale", 1.0, maxf(duration * 0.4, 0.01)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_end_slowmo)
	_slowmo_tween = tw


## ------------------------------------------------------------------ event handlers

func _on_station_upgraded(station: int, _upgrade_id: String, _levels: int, _new_level: int) -> void:
	var now := Time.get_ticks_msec()
	_pending_station = station
	_pending_ms = now
	var known: Variant = _station_tp.get(station)
	_pending_tp_before = float(known) if known != null else -1.0
	if now - _last_burst_ms >= BURST_THROTTLE_MS:
		_last_burst_ms = now
		coin_burst(_screen_center())


func _on_sim_stats(stats: Dictionary) -> void:
	var stations: Variant = stats.get("stations")
	if typeof(stations) != TYPE_ARRAY:
		return
	if _pending_station >= 0:
		_resolve_upgrade_text(stations)
	for i in stations.size():
		var view: Variant = stations[i]
		if typeof(view) != TYPE_DICTIONARY:
			continue
		var tp: Variant = view.get("throughput")
		if typeof(tp) == TYPE_FLOAT or typeof(tp) == TYPE_INT:
			_station_tp[i] = float(tp)


## After an upgrade, show "+X/s" from that station's effective-throughput delta
## as soon as the next snapshot lands (line pps ramps too slowly to read there).
func _resolve_upgrade_text(stations: Array) -> void:
	if Time.get_ticks_msec() - _pending_ms > UPGRADE_FX_WINDOW_MS:
		_pending_station = -1
		return
	if _pending_station >= stations.size():
		_pending_station = -1
		return
	var view: Variant = stations[_pending_station]
	if typeof(view) != TYPE_DICTIONARY:
		_pending_station = -1
		return
	var tp: Variant = view.get("throughput")
	if typeof(tp) != TYPE_FLOAT and typeof(tp) != TYPE_INT:
		_pending_station = -1
		return
	var delta := float(tp) - _pending_tp_before
	if _pending_tp_before >= 0.0 and delta > 0.0005:
		float_text("+%s/s" % _fmt_rate(delta), _screen_center_left(), GREEN)
	_pending_station = -1


func _on_bottleneck_cleared(_station: int) -> void:
	slowmo()
	shake(0.6)
	_flash()


func _on_prestige_performed(_cip_gained: int, _new_multiplier: float) -> void:
	shake(1.0)
	if _reduce_motion():
		return
	var c := _screen_center()
	var vp := _viewport_size()
	_spawn_burst(c, 26, 1.5)
	_spawn_burst(c + Vector2(-vp.x * 0.16, vp.y * 0.05), 16, 1.1)
	_spawn_burst(c + Vector2(vp.x * 0.16, vp.y * 0.05), 16, 1.1)


func _on_milestone_reached(_id: String, kp_gained: int) -> void:
	var vp := _viewport_size()
	float_text("+%d KP" % kp_gained, Vector2(vp.x * 0.5, vp.y * 0.16), AMBER)


## ------------------------------------------------------------------ internals

func _process(delta: float) -> void:
	if _shake_time_left <= 0.0:
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	_shake_time_left -= real_dt
	if _shake_cam == null or not is_instance_valid(_shake_cam):
		_shake_cam = null
		_shake_time_left = 0.0
		_shake_strength = 0.0
		return
	if _shake_time_left <= 0.0:
		_restore_cam()
		return
	var decay := _shake_time_left / SHAKE_DURATION
	var amp := SHAKE_MAX_OFFSET * _shake_strength * decay * decay
	_shake_cam.h_offset = _shake_base_h + randf_range(-amp, amp)
	_shake_cam.v_offset = _shake_base_v + randf_range(-amp, amp)


func _restore_cam() -> void:
	if _shake_cam != null and is_instance_valid(_shake_cam):
		_shake_cam.h_offset = _shake_base_h
		_shake_cam.v_offset = _shake_base_v
	_shake_cam = null
	_shake_time_left = 0.0
	_shake_strength = 0.0


func _end_slowmo() -> void:
	Engine.time_scale = 1.0
	_slowmo_tween = null


func _build_flash_rect() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, FLASH_COLOR.a * 0.3),
		Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, FLASH_COLOR.a * 0.55),
		FLASH_COLOR,
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	_flash_rect = TextureRect.new()
	_flash_rect.name = "GreenFlash"
	_flash_rect.texture = tex
	_flash_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_flash_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.visible = false
	_canvas.add_child(_flash_rect)


## Very brief full-screen green vignette (bottleneck cleared). Skipped when
## reduce_motion — the chime + world visuals still mark the moment.
func _flash() -> void:
	if _flash_rect == null or _reduce_motion():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.modulate = Color(1, 1, 1, 1)
	_flash_rect.visible = true
	var tw := create_tween()
	tw.tween_property(_flash_rect, "modulate:a", 0.0, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_hide_flash)
	_flash_tween = tw


func _hide_flash() -> void:
	if _flash_rect != null and is_instance_valid(_flash_rect):
		_flash_rect.visible = false


func _build_particle_texture() -> void:
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_particle_tex = ImageTexture.create_from_image(img)


## CPUParticles2D (Compatibility-renderer safe) burst; frees itself on finish.
func _spawn_burst(screen_pos: Vector2, amount: int, power: float) -> void:
	if _canvas == null:
		return
	var p := CPUParticles2D.new()
	p.position = screen_pos
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 55.0
	p.gravity = Vector2(0, 980)
	p.initial_velocity_min = 220.0 * power
	p.initial_velocity_max = 420.0 * power
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.texture = _particle_tex
	p.color = AMBER
	_canvas.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	get_tree().create_timer(2.5).timeout.connect(_free_if_valid.bind(p))


func _free_if_valid(n: Variant) -> void:
	# Untyped on purpose: the bound node may already be freed when the fallback timer
	# fires (a freed instance cannot pass through a Node-typed parameter).
	if n != null and is_instance_valid(n):
		n.queue_free()


func _obtain_label() -> Label:
	var lbl: Label = null
	if _float_free.size() > 0:
		lbl = _float_free.pop_back()
	elif _float_live.size() >= FLOAT_CAP:
		lbl = _float_live.pop_front()	# recycle the oldest under spam
		_kill_label_tween(lbl)
	else:
		lbl = _make_label()
	if lbl == null or not is_instance_valid(lbl):
		return null
	_float_live.append(lbl)
	return lbl


func _make_label() -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.visible = false
	_canvas.add_child(lbl)
	return lbl


func _release_label(lbl: Label) -> void:
	if lbl == null or not is_instance_valid(lbl):
		_float_live = _float_live.filter(_label_valid)
		return
	lbl.visible = false
	lbl.remove_meta("juice_tween")
	_float_live.erase(lbl)
	_float_free.append(lbl)


func _label_valid(lbl: Label) -> bool:
	return lbl != null and is_instance_valid(lbl)


func _kill_label_tween(lbl: Label) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	if lbl.has_meta("juice_tween"):
		var tw: Variant = lbl.get_meta("juice_tween")
		if tw != null and (tw as Tween).is_valid():
			(tw as Tween).kill()
		lbl.remove_meta("juice_tween")


func _count_step_float(v: float, label: Label, fmt: Callable) -> void:
	_apply_count(label, fmt, v)


func _count_step_big(v: float, label: Label, fmt: Callable) -> void:
	_apply_count(label, fmt, BigNum.from_float(v))


func _apply_count(label: Label, fmt: Callable, value: Variant) -> void:
	if label == null or not is_instance_valid(label) or not fmt.is_valid():
		return
	var out: Variant = fmt.call(value)
	if typeof(out) == TYPE_STRING:
		label.text = out


func _is_bignum(v: Variant) -> bool:
	return typeof(v) == TYPE_OBJECT and v != null and v.has_method("to_float")


func _float_e(v: Variant) -> int:
	var f := absf(float(v))
	if f < 1.0:
		return 0
	if is_inf(f):
		return 308
	return int(floor(log(f) / log(10.0)))


func _kill_tracked(tracker: Dictionary, key: int) -> void:
	if not tracker.has(key):
		return
	var tw: Variant = tracker[key]
	if tw != null and (tw as Tween).is_valid():
		(tw as Tween).kill()
	tracker.erase(key)


func _untrack(tracker: Dictionary, key: int) -> void:
	tracker.erase(key)


func _fmt_rate(v: float) -> String:
	if v >= 1000.0:
		var bn = BigNum.from_float(v)
		var s: String = bn.format(_number_format(), 2)
		return s
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1280, 720)
	return vp.get_visible_rect().size


func _screen_center() -> Vector2:
	return _viewport_size() * 0.5


func _screen_center_left() -> Vector2:
	var vp := _viewport_size()
	return Vector2(vp.x * 0.3, vp.y * 0.42)


## SettingsService lands in parallel — read every field defensively.
func _reduce_motion() -> bool:
	var ss := get_node_or_null("/root/SettingsService")
	if ss == null:
		return false
	var v: Variant = ss.get("reduce_motion")
	return typeof(v) == TYPE_BOOL and v


func _shake_setting() -> float:
	var ss := get_node_or_null("/root/SettingsService")
	if ss == null:
		return 0.3
	var v: Variant = ss.get("screen_shake")
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return clampf(float(v), 0.0, 1.0)
	return 0.3


func _number_format() -> String:
	var ss := get_node_or_null("/root/SettingsService")
	if ss != null:
		var v: Variant = ss.get("number_format")
		if typeof(v) == TYPE_STRING and v == "scientific":
			return "scientific"
	return "suffix"
