## CameraRig — default orbit management camera (RMB orbit, wheel zoom, MMB/edge pan, smooth
## lerp, auto-frames the unlocked line) plus the first-person Gemba Walk mode on `toggle_walk`
## (Tab). Both modes raycast-click stations → EventBus.station_selected; emits camera_mode_changed.
## Touch: 1-finger drag orbits, tap selects, 2-finger pinch zooms, 2-finger drag pans;
## edge pan is disabled on touchscreens and touch always wins over emulated mouse events.
extends Node3D

const WorldLib = preload("res://src/world/world_lib.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const InputSetup = preload("res://src/core/input_setup.gd")

signal hover_changed(station_index: int)

const PITCH_MIN := -1.32
const PITCH_MAX := -0.2
const DIST_MIN := 6.0
const DIST_MAX := 48.0
const EDGE_PX := 16.0
const EDGE_PAN_IDLE_MS := 1500	# edge pan only while the mouse has moved recently
const WALK_SPEED := 4.3
const WALK_EYE := 1.62
const TAP_MAX_PX := 10.0		# a touch that moved less than this ...
const TAP_MAX_MS := 300			# ... and released quicker than this = station-select tap
const TOUCH_ORBIT_FACTOR := 0.0045
const FRAME_ASPECT_REF := 1.6	# below this viewport aspect, frame_line zooms out to fit

var mode: int = SimTypes.CAMERA_ORBIT

var _orbit_cam: Camera3D = null
var _walk_body: CharacterBody3D = null
var _head: Node3D = null
var _walk_cam: Camera3D = null

# Orbit: desired vs. smoothed-actual state.
var _target := Vector3(8.0, 0.9, 0.5)
var _yaw := 0.38
var _pitch := -0.52
var _dist := 21.0
var _cur_target := Vector3(8.0, 0.9, 0.5)
var _cur_yaw := 0.38
var _cur_pitch := -0.52
var _cur_dist := 21.0

var _orbiting := false
var _panning := false
var _last_motion_ms: int = -1000000
var _lmb_down := false
var _lmb_down_pos := Vector2.ZERO
var _pending_click := false
var _pending_click_pos := Vector2.ZERO
var _hover_idx := -1
var _walk_yaw := 0.0
var _walk_pitch := 0.0
var _bob_t := 0.0
var _sens := 1.0
var _reduce_motion := false

# Touch gesture state (per-index; only touches whose press reached _unhandled_input —
# i.e. not consumed by a GUI Control — are tracked).
var _touchscreen := false
var _touch_pts: Dictionary = {}		# index -> latest position
var _touch_start: Dictionary = {}	# index -> press position
var _touch_ms: Dictionary = {}		# index -> press tick (msec)
var _multi_gesture := false			# once 2+ fingers were down, releases never tap-select
var _pinch_sep := 0.0				# finger separation when the 2-finger gesture began
var _pinch_dist := 0.0				# _dist when the 2-finger gesture began

# Last framed line extent (re-framed when the viewport aspect changes class, e.g. rotation).
var _frame_min_x := 0.0
var _frame_max_x := 0.0
var _frame_aspect := 0.0
var _framed := false


# ---------------------------------------------------------------- pure gesture math (tested)

## Two-finger pinch zoom: the camera distance scales with start/current finger
## separation, clamped exactly like the mouse wheel.
static func pinch_zoom(base_dist: float, start_sep: float, cur_sep: float) -> float:
	if start_sep <= 0.0 or cur_sep <= 0.0:
		return clampf(base_dist, DIST_MIN, DIST_MAX)
	return clampf(base_dist * start_sep / cur_sep, DIST_MIN, DIST_MAX)


## True when a touch press/release pair still counts as a station-select tap.
static func is_tap(moved_px: float, held_ms: int) -> bool:
	return moved_px < TAP_MAX_PX and held_ms < TAP_MAX_MS


## Distance multiplier so the framed line still fits horizontally on narrow (portrait)
## viewports: 1.0 at/above the 1.6 reference aspect, growing as the view narrows.
static func frame_dist_scale(aspect: float) -> float:
	if aspect <= 0.01:
		return 1.0
	return clampf(FRAME_ASPECT_REF / aspect, 1.0, 4.0)


func _ready() -> void:
	name = "CameraRig"
	if not InputMap.has_action("toggle_walk"):
		InputSetup.register_actions()
	_orbit_cam = Camera3D.new()
	_orbit_cam.name = "OrbitCamera"
	_orbit_cam.fov = 52.0
	_orbit_cam.near = 0.1
	_orbit_cam.far = 320.0
	add_child(_orbit_cam)
	_orbit_cam.current = true

	_walk_body = CharacterBody3D.new()
	_walk_body.name = "WalkBody"
	_walk_body.collision_layer = 0
	_walk_body.collision_mask = WorldLib.LAYER_FLOOR | WorldLib.LAYER_STATION
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.88, 0.0)
	_walk_body.add_child(shape)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, WALK_EYE, 0.0)
	_walk_body.add_child(_head)
	_walk_cam = Camera3D.new()
	_walk_cam.name = "WalkCamera"
	_walk_cam.fov = 72.0
	_walk_cam.near = 0.05
	_walk_cam.far = 260.0
	_head.add_child(_walk_cam)
	add_child(_walk_body)
	_walk_body.position = Vector3(7.0, 0.2, 4.6)

	_touchscreen = DisplayServer.is_touchscreen_available()
	_refresh_settings("")
	EventBus.settings_changed.connect(_on_settings_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_apply_orbit_transform()


## Re-frame the orbit camera around the current unlocked line extent (called by FactoryWorld
## on rebuild and on station_unlocked, so the view grows with the factory). On narrow
## (portrait) viewports the distance is scaled up so the whole line still fits.
func frame_line(min_x: float, max_x: float) -> void:
	_frame_min_x = min_x
	_frame_max_x = max_x
	_frame_aspect = _viewport_aspect()
	_framed = true
	_target = Vector3((min_x + max_x) * 0.5 + 1.0, 0.9, 0.5)
	var dist := clampf((max_x - min_x) * 0.55 + 8.0, 14.0, DIST_MAX)
	_dist = clampf(dist * frame_dist_scale(_frame_aspect), 14.0, DIST_MAX)
	_clamp_target()


## Rotation / big aspect changes re-frame the last extent (small desktop window resizes
## never fight a user-adjusted camera).
func _on_viewport_resized() -> void:
	if not _framed or mode != SimTypes.CAMERA_ORBIT:
		return
	var aspect := _viewport_aspect()
	if _frame_aspect > 0.0 and absf(aspect - _frame_aspect) / _frame_aspect > 0.2:
		frame_line(_frame_min_x, _frame_max_x)


func _viewport_aspect() -> float:
	var vp := get_viewport()
	if vp == null:
		return FRAME_ASPECT_REF
	var s: Vector2 = vp.get_visible_rect().size
	if s.y <= 0.0:
		return FRAME_ASPECT_REF
	return s.x / s.y


func _on_settings_changed(key: String, _value: Variant) -> void:
	_refresh_settings(key)


func _refresh_settings(_key: String) -> void:
	_sens = WorldLib.cam_sensitivity()
	_reduce_motion = WorldLib.reduce_motion()


## toggle_walk is handled in _input, ahead of GUI focus traversal: Tab is also Godot's
## built-in ui_focus_next, so by _unhandled_input the UI has already eaten it.
## Also tracks real mouse motion here (UI-consumed motion never reaches _unhandled_input),
## which gates edge panning: a parked cursor must not drift the camera.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_motion_ms = Time.get_ticks_msec()
		return
	if not event.is_action_pressed("toggle_walk"):
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	_set_mode(SimTypes.CAMERA_WALK if mode == SimTypes.CAMERA_ORBIT else SimTypes.CAMERA_ORBIT)
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode == SimTypes.CAMERA_WALK:
		if event.is_action_pressed("pause_menu"):
			_set_mode(SimTypes.CAMERA_ORBIT)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("interact"):
			_queue_click(_viewport_center())
			return
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var rel: Vector2 = event.relative
			_walk_yaw = wrapf(_walk_yaw - rel.x * 0.0032 * _sens, -PI, PI)
			_walk_pitch = clampf(_walk_pitch - rel.y * 0.0032 * _sens, -1.4, 1.4)
			_walk_body.rotation.y = _walk_yaw
			_head.rotation.x = _walk_pitch
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_queue_click(_viewport_center())
		return
	# --- Orbit mode ---
	# Touch first: gestures own the camera on touch devices. Mouse events emulated from
	# touches (device == DEVICE_ID_EMULATION, and anything arriving while fingers are
	# down) are ignored so the camera is never double-driven.
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_handle_touch_drag(event as InputEventScreenDrag)
		return
	if (event is InputEventMouseButton or event is InputEventMouseMotion) \
			and (event.device == InputEvent.DEVICE_ID_EMULATION or not _touch_pts.is_empty()):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_dist = clampf(_dist * 0.87, DIST_MIN, DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_dist = clampf(_dist / 0.87, DIST_MIN, DIST_MAX)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_lmb_down = true
					_lmb_down_pos = mb.position
				elif _lmb_down:
					_lmb_down = false
					if mb.position.distance_to(_lmb_down_pos) < 8.0:
						_queue_click(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw = wrapf(_yaw - mm.relative.x * 0.0055 * _sens, -PI, PI)
			_pitch = clampf(_pitch - mm.relative.y * 0.0055 * _sens, PITCH_MIN, PITCH_MAX)
		elif _panning:
			var yaw_b := Basis(Vector3.UP, _cur_yaw)
			var right := yaw_b * Vector3.RIGHT
			var fwd := yaw_b * Vector3(0.0, 0.0, -1.0)
			_target += (right * -mm.relative.x + fwd * mm.relative.y) * _cur_dist * 0.0016
			_clamp_target()


# ---------------------------------------------------------------- touch gestures

## Press/release bookkeeping. Only presses that reached _unhandled_input are tracked, so
## touches consumed by GUI Controls never move the camera; stray releases are ignored.
func _handle_touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		_touch_pts[ev.index] = ev.position
		_touch_start[ev.index] = ev.position
		_touch_ms[ev.index] = Time.get_ticks_msec()
		if _touch_pts.size() == 2:
			_multi_gesture = true
			_begin_pinch()
		elif _touch_pts.size() > 2:
			_multi_gesture = true
		return
	if not _touch_pts.has(ev.index):
		return
	var start: Vector2 = _touch_start.get(ev.index, ev.position)
	var held := Time.get_ticks_msec() - int(_touch_ms.get(ev.index, 0))
	var single: bool = _touch_pts.size() == 1 and not _multi_gesture
	_touch_pts.erase(ev.index)
	_touch_start.erase(ev.index)
	_touch_ms.erase(ev.index)
	if single and is_tap(ev.position.distance_to(start), held):
		_queue_click(ev.position)	# tap = station select (same raycast path as clicks)
	if _touch_pts.size() == 2:
		_begin_pinch()	# 3 fingers down to 2: restart the pinch baseline
	elif _touch_pts.is_empty():
		_multi_gesture = false


## 1 finger = orbit; 2 fingers = pinch zoom + pan (each finger's relative at half
## weight approximates the midpoint delta, so a symmetric pinch pans nothing).
func _handle_touch_drag(ev: InputEventScreenDrag) -> void:
	if not _touch_pts.has(ev.index):
		return
	_touch_pts[ev.index] = ev.position
	if _touch_pts.size() == 1 and not _multi_gesture:
		_yaw = wrapf(_yaw - ev.relative.x * TOUCH_ORBIT_FACTOR * _sens, -PI, PI)
		_pitch = clampf(_pitch - ev.relative.y * TOUCH_ORBIT_FACTOR * _sens, PITCH_MIN, PITCH_MAX)
	elif _touch_pts.size() == 2:
		var keys: Array = _touch_pts.keys()
		var a: Vector2 = _touch_pts[keys[0]]
		var b: Vector2 = _touch_pts[keys[1]]
		_dist = pinch_zoom(_pinch_dist, _pinch_sep, a.distance_to(b))
		var yaw_b := Basis(Vector3.UP, _cur_yaw)
		var right := yaw_b * Vector3.RIGHT
		var fwd := yaw_b * Vector3(0.0, 0.0, -1.0)
		_target += (right * -ev.relative.x + fwd * ev.relative.y) * _cur_dist * 0.0016 * 0.5
		_clamp_target()


func _begin_pinch() -> void:
	var keys: Array = _touch_pts.keys()
	if keys.size() < 2:
		return
	var a: Vector2 = _touch_pts[keys[0]]
	var b: Vector2 = _touch_pts[keys[1]]
	_pinch_sep = maxf(a.distance_to(b), 1.0)
	_pinch_dist = _dist


func _process(delta: float) -> void:
	if mode == SimTypes.CAMERA_ORBIT:
		_edge_pan(delta)
		var k := minf(1.0, delta * (16.0 if _reduce_motion else 9.0))
		_cur_yaw = lerp_angle(_cur_yaw, _yaw, k)
		_cur_pitch = lerpf(_cur_pitch, _pitch, k)
		_cur_dist = lerpf(_cur_dist, _dist, k)
		_cur_target = _cur_target.lerp(_target, k)
		_apply_orbit_transform()


func _apply_orbit_transform() -> void:
	var b := Basis(Vector3.UP, _cur_yaw) * Basis(Vector3.RIGHT, _cur_pitch)
	var pos := _cur_target + b * Vector3(0.0, 0.0, _cur_dist)
	_orbit_cam.transform = Transform3D(b, pos)
	# Hide ceiling clutter while the management camera is above it (walk cam always sees it).
	_orbit_cam.set_cull_mask_value(WorldLib.RENDER_LAYER_CEILING, pos.y < WorldLib.CEILING_VIS_HEIGHT)


func _edge_pan(delta: float) -> void:
	if _touchscreen:
		return	# no cursor parking on touch devices — edge pan would fight gestures
	if _orbiting or _panning or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	var vp := get_viewport()
	if vp == null:
		return
	if Time.get_ticks_msec() - _last_motion_ms > EDGE_PAN_IDLE_MS:
		return	# cursor parked (or never moved) — no drift
	if vp.gui_get_hovered_control() != null:
		return	# cursor over the HUD panels that flank the screen edges
	var mp := vp.get_mouse_position()
	var size: Vector2 = vp.get_visible_rect().size
	if mp.x < 0.0 or mp.y < 0.0 or mp.x > size.x or mp.y > size.y:
		return
	var dir := Vector2.ZERO
	if mp.x < EDGE_PX:
		dir.x = -1.0
	elif mp.x > size.x - EDGE_PX:
		dir.x = 1.0
	if mp.y < EDGE_PX:
		dir.y = -1.0
	elif mp.y > size.y - EDGE_PX:
		dir.y = 1.0
	if dir == Vector2.ZERO:
		return
	var yaw_b := Basis(Vector3.UP, _cur_yaw)
	var right := yaw_b * Vector3.RIGHT
	var fwd := yaw_b * Vector3(0.0, 0.0, -1.0)
	var speed := 0.28 + _cur_dist * 0.45
	_target += (right * dir.x + fwd * -dir.y) * speed * delta
	_clamp_target()


func _clamp_target() -> void:
	_target.x = clampf(_target.x, WorldLib.FLOOR_MIN_X + 2.0, WorldLib.FLOOR_MAX_X - 2.0)
	_target.z = clampf(_target.z, WorldLib.FLOOR_MIN_Z + 2.0, WorldLib.FLOOR_MAX_Z - 2.0)
	_target.y = 0.9


func _viewport_center() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var size: Vector2 = vp.get_visible_rect().size
	return size * 0.5


func _queue_click(pos: Vector2) -> void:
	_pending_click = true
	_pending_click_pos = pos


func _physics_process(delta: float) -> void:
	if mode == SimTypes.CAMERA_WALK:
		_walk_move(delta)
	if _pending_click:
		_pending_click = false
		var idx := _ray_station(_pending_click_pos)
		if idx >= 0:
			EventBus.station_selected.emit(idx)
	if mode == SimTypes.CAMERA_ORBIT and not _orbiting and not _panning:
		var vp := get_viewport()
		if vp != null:
			var mp := vp.get_mouse_position()
			var size: Vector2 = vp.get_visible_rect().size
			var idx := -1
			if mp.x >= 0.0 and mp.y >= 0.0 and mp.x <= size.x and mp.y <= size.y:
				idx = _ray_station(mp)
			if idx != _hover_idx:
				_hover_idx = idx
				hover_changed.emit(idx)
	elif _hover_idx != -1 and mode == SimTypes.CAMERA_WALK:
		_hover_idx = -1
		hover_changed.emit(-1)


func _walk_move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var b := Basis(Vector3.UP, _walk_yaw)
	var wish := b * Vector3(input.x, 0.0, input.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	wish *= WALK_SPEED
	var v := _walk_body.velocity
	var k := minf(1.0, delta * 10.0)
	v.x = lerpf(v.x, wish.x, k)
	v.z = lerpf(v.z, wish.z, k)
	if _walk_body.is_on_floor():
		v.y = -0.6
	else:
		v.y -= 24.0 * delta
	_walk_body.velocity = v
	_walk_body.move_and_slide()
	# Hard floor-bounds clamp: the Gemba Walk never leaves the shop floor.
	var p := _walk_body.position
	p.x = clampf(p.x, WorldLib.FLOOR_MIN_X + WorldLib.WALK_MARGIN, WorldLib.FLOOR_MAX_X - WorldLib.WALK_MARGIN)
	p.z = clampf(p.z, WorldLib.FLOOR_MIN_Z + WorldLib.WALK_MARGIN, WorldLib.FLOOR_MAX_Z - WorldLib.WALK_MARGIN)
	if p.y < -0.4:
		p.y = 0.2
		v.y = 0.0
		_walk_body.velocity = v
	_walk_body.position = p
	# Subtle head bob while moving.
	var planar := Vector2(v.x, v.z).length()
	if planar > 0.4 and not _reduce_motion:
		_bob_t += delta * planar * 1.9
		_head.position.y = WALK_EYE + sin(_bob_t) * 0.032
	else:
		_head.position.y = lerpf(_head.position.y, WALK_EYE, minf(1.0, delta * 6.0))


func _ray_station(screen_pos: Vector2) -> int:
	var cam := _walk_cam if mode == SimTypes.CAMERA_WALK else _orbit_cam
	if cam == null or not cam.is_inside_tree():
		return -1
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 300.0
	var params := PhysicsRayQueryParameters3D.create(from, to, WorldLib.LAYER_STATION)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	if hit.has("collider"):
		var col: Object = hit["collider"]
		if col != null and col.has_meta("station_index"):
			return int(col.get_meta("station_index", -1))
	return -1


func _set_mode(m: int) -> void:
	if m == mode:
		return
	mode = m
	if mode == SimTypes.CAMERA_WALK:
		var spawn_x := clampf(_cur_target.x, WorldLib.FLOOR_MIN_X + 3.0, WorldLib.FLOOR_MAX_X - 3.0)
		_walk_body.position = Vector3(spawn_x, 0.25, 4.7)
		_walk_body.velocity = Vector3.ZERO
		_walk_yaw = 0.0
		_walk_pitch = -0.05
		_walk_body.rotation.y = _walk_yaw
		_head.rotation.x = _walk_pitch
		_head.position.y = WALK_EYE
		_walk_cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_orbit_cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_orbiting = false
		_panning = false
	EventBus.camera_mode_changed.emit(mode)
