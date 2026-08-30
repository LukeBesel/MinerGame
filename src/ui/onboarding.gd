## Onboarding — first-run spotlight overlay. On load_completed, when
## SettingsService.onboarding_done is falsy and Data.db has onboarding steps, dims the
## whole screen (four blocker rects drawn in _draw — no shaders) with a rounded cutout
## over the current step's target (resolved via the OnboardTargets registry; missing
## target = no hole, bubble centered) plus a text bubble with Next/Skip. "on_upgrade"
## steps hide Next and auto-advance on EventBus.station_upgraded. Skip is always visible,
## Esc also skips; skip/finish writes onboarding_done=true (guarded). Clicks pass through
## the hole so the spotlit control stays usable. Reduce-motion: spotlight snaps.
extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")

signal active_changed(active: bool)

const HOLE_PAD := 10.0
const HOLE_RADIUS := 12.0
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.62)
const BUBBLE_MAX_W := 380.0
const BUBBLE_GAP := 14.0
const EDGE := 8.0
const SMOOTH_RATE := 14.0		# spotlight follow speed (1/s); ignored under reduce-motion
const CORNER_SEGMENTS := 8

var _targets = null
var _steps: Array = []
var _index := -1
var _active := false
var _ran := false				# one attempt per session

var _hole := Rect2()			# where the spotlight wants to be (global space)
var _hole_shown := Rect2()		# where it is drawn this frame (global space)
var _blockers: Array = []
var _bubble: PanelContainer
var _text: Label
var _skip_btn: Button
var _next_btn: Button
var _ring_box: StyleBoxFlat


# ---------------------------------------------------------------- pure helpers (tested)

## Accepts the loader shape (Array of step dicts) or the {steps:[...]} document shape.
## Keeps only dicts with a non-empty text_key; fills id/target defaults and normalizes
## advance to "next"|"on_upgrade".
static func normalize_steps(v: Variant) -> Array:
	var arr: Array = []
	if typeof(v) == TYPE_ARRAY:
		arr = v
	elif typeof(v) == TYPE_DICTIONARY:
		var s_v: Variant = (v as Dictionary).get("steps", [])
		if typeof(s_v) == TYPE_ARRAY:
			arr = s_v
	var out: Array = []
	for step_v in arr:
		if typeof(step_v) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = step_v
		var text_key := str(step.get("text_key", ""))
		if text_key == "":
			continue
		out.append({
			"id": str(step.get("id", "")),
			"target": str(step.get("target", "")),
			"text_key": text_key,
			"advance": "on_upgrade" if str(step.get("advance", "")) == "on_upgrade" else "next",
		})
	return out


## Truthiness of the (possibly still unshipped) onboarding_done setting value.
static func is_done_value(v: Variant) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING:
			return str(v) == "true" or str(v) == "1"
	return false


static func should_show(done_value: Variant, steps: Array) -> bool:
	return steps.size() > 0 and not is_done_value(done_value)


## "on_upgrade" steps hide their Next button (they advance via station_upgraded).
static func shows_next(step: Dictionary) -> bool:
	return str(step.get("advance", "next")) != "on_upgrade"


static func next_label_key(steps: Array, index: int) -> String:
	return "ui.done" if index >= steps.size() - 1 else "ui.next"


## The four rects tiling bounds around the (clamped) hole: [top, bottom, left, right].
## Empty/degenerate hole -> [bounds, 0, 0, 0] (full dim). Rects never overlap.
static func side_rects(bounds: Rect2, hole: Rect2) -> Array:
	var h := hole.intersection(bounds)
	if h.size.x <= 0.0 or h.size.y <= 0.0:
		return [bounds, Rect2(), Rect2(), Rect2()]
	var top := Rect2(bounds.position, Vector2(bounds.size.x, h.position.y - bounds.position.y))
	var bottom := Rect2(Vector2(bounds.position.x, h.end.y), Vector2(bounds.size.x, bounds.end.y - h.end.y))
	var left := Rect2(Vector2(bounds.position.x, h.position.y), Vector2(h.position.x - bounds.position.x, h.size.y))
	var right := Rect2(Vector2(h.end.x, h.position.y), Vector2(bounds.end.x - h.end.x, h.size.y))
	return [top, bottom, left, right]


# ---------------------------------------------------------------- build

func setup(targets) -> void:
	_targets = targets


func _ready() -> void:
	name = "Onboarding"
	UiUtil.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE	# the blockers stop input; the hole lets it through
	visible = false
	set_process(false)
	resized.connect(queue_redraw)

	for i in 4:
		var b := Control.new()
		b.name = "Blocker%d" % i
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(b)
		_blockers.append(b)

	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.theme_type_variation = "ModalPanel"
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bubble)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_bubble.add_child(v)
	_text = Label.new()
	_text.theme_type_variation = "Label"
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_skip_btn = Button.new()
	_skip_btn.theme_type_variation = "GhostButton"
	_skip_btn.text = L.t("ui.skip")
	_skip_btn.custom_minimum_size = Vector2(84, 44)
	_skip_btn.pressed.connect(_on_skip_pressed)
	row.add_child(_skip_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_next_btn = Button.new()
	_next_btn.theme_type_variation = "AccentButton"
	_next_btn.custom_minimum_size = Vector2(108, 44)
	_next_btn.pressed.connect(_on_next_pressed)
	row.add_child(_next_btn)

	# Amber rounded ring stroked over the hole edge (its corners visually round the cutout
	# together with the corner-notch fills in _draw).
	_ring_box = StyleBoxFlat.new()
	_ring_box.draw_center = false
	_ring_box.border_color = UiTheme.COL_AMBER
	_ring_box.set_border_width_all(2)
	_ring_box.set_corner_radius_all(int(HOLE_RADIUS))
	_ring_box.anti_aliasing = true

	EventBus.load_completed.connect(_on_load_completed)
	EventBus.station_upgraded.connect(_on_station_upgraded)


# ---------------------------------------------------------------- flow

func _on_load_completed() -> void:
	if _ran or _active:
		return
	_steps = normalize_steps(UiUtil.db().get("onboarding"))
	if not should_show(UiUtil.setting("onboarding_done", false), _steps):
		return
	_ran = true
	_active = true
	visible = true
	set_process(true)
	_index = -1
	_hole = Rect2()
	_hole_shown = Rect2()
	_advance()
	active_changed.emit(true)


func _advance() -> void:
	_index += 1
	if _index >= _steps.size():
		_finish()
		return
	_show_step()


func _show_step() -> void:
	var step := _current_step()
	UiUtil.set_label(_text, L.t(str(step.get("text_key", ""))))
	UiUtil.fit_label(_text, BUBBLE_MAX_W)
	var with_next := shows_next(step)
	_next_btn.visible = with_next
	if with_next:
		UiUtil.set_btn(_next_btn, L.t(next_label_key(_steps, _index)))
	_bubble.reset_size()
	_update_hole(0.0)
	_layout_blockers()
	_position_bubble()
	if with_next:
		_next_btn.grab_focus()
	else:
		_skip_btn.grab_focus()


func _current_step() -> Dictionary:
	if _index >= 0 and _index < _steps.size():
		var s: Variant = _steps[_index]
		if typeof(s) == TYPE_DICTIONARY:
			return s
	return {}


func _on_next_pressed() -> void:
	if AudioDirector.has_method("play"):
		AudioDirector.play("click")
	_advance()


func _on_skip_pressed() -> void:
	_finish()


func _on_station_upgraded(_station: int, _upgrade_id: String, _levels: int, _new_level: int) -> void:
	if _active and not shows_next(_current_step()):
		_advance()


func _finish() -> void:
	if not _active:
		return
	_active = false
	visible = false
	set_process(false)
	UiUtil.write_setting("onboarding_done", true)	# no-op until the field ships
	active_changed.emit(false)


func _input(event: InputEvent) -> void:
	if _active and event.is_action_pressed("ui_cancel"):
		_finish()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- spotlight

func _process(delta: float) -> void:
	if not _active:
		return
	_update_hole(delta)
	_layout_blockers()
	_position_bubble()


func _update_hole(delta: float) -> void:
	var step := _current_step()
	var target_rect := Rect2()
	if _targets != null and _targets.has_method("rect"):
		var rv: Variant = _targets.rect(str(step.get("target", "")))
		if rv is Rect2:
			target_rect = rv
	var want := Rect2()
	if target_rect.size.x > 0.0 and target_rect.size.y > 0.0:
		want = target_rect.grow(HOLE_PAD)
	_hole = want
	var snap: bool = UiUtil.reduce_motion() \
			or _hole_shown.size.x <= 0.0 or want.size.x <= 0.0 or delta <= 0.0
	if snap:
		if _hole_shown != want:
			_hole_shown = want
			queue_redraw()
		return
	var f := 1.0 - exp(-SMOOTH_RATE * delta)
	var pos := _hole_shown.position.lerp(want.position, f)
	var sz := _hole_shown.size.lerp(want.size, f)
	if pos.distance_to(want.position) < 0.5 and sz.distance_to(want.size) < 0.5:
		pos = want.position
		sz = want.size
	var next := Rect2(pos, sz)
	if next != _hole_shown:
		_hole_shown = next
		queue_redraw()


## _hole_shown is global; convert into this control's local space for draw/layout.
func _local_hole() -> Rect2:
	if _hole_shown.size.x <= 0.0 or _hole_shown.size.y <= 0.0:
		return Rect2()
	return Rect2(_hole_shown.position - global_position, _hole_shown.size)


func _layout_blockers() -> void:
	var rects: Array = side_rects(Rect2(Vector2.ZERO, size), _local_hole())
	for i in _blockers.size():
		var b: Control = _blockers[i]
		var r: Rect2 = rects[i] if i < rects.size() else Rect2()
		b.position = r.position
		b.size = r.size
		b.visible = r.size.x > 0.0 and r.size.y > 0.0


func _position_bubble() -> void:
	var sz := _bubble.size
	var bounds := size
	var hole := _local_hole()
	var pos := (bounds - sz) * 0.5
	if hole.size.y > 0.0:
		var x := clampf(hole.position.x + (hole.size.x - sz.x) * 0.5,
				EDGE, maxf(EDGE, bounds.x - sz.x - EDGE))
		var below := hole.end.y + BUBBLE_GAP
		var above := hole.position.y - BUBBLE_GAP - sz.y
		if below + sz.y <= bounds.y - EDGE:
			pos = Vector2(x, below)
		elif above >= EDGE:
			pos = Vector2(x, above)
		else:
			pos = Vector2(x, clampf((bounds.y - sz.y) * 0.5, EDGE, maxf(EDGE, bounds.y - sz.y - EDGE)))
	_bubble.position = pos


func _draw() -> void:
	if not _active:
		return
	var bounds := Rect2(Vector2.ZERO, size)
	var hole := _local_hole()
	var rects: Array = side_rects(bounds, hole)
	for r_v in rects:
		var r: Rect2 = r_v
		if r.size.x > 0.0 and r.size.y > 0.0:
			draw_rect(r, DIM_COLOR, true)
	var h := hole.intersection(bounds)
	if h.size.x <= 0.0 or h.size.y <= 0.0:
		return
	var radius := minf(HOLE_RADIUS, minf(h.size.x, h.size.y) * 0.5)
	_draw_corner(h.position, Vector2(1, 1), radius)
	_draw_corner(Vector2(h.end.x, h.position.y), Vector2(-1, 1), radius)
	_draw_corner(h.end, Vector2(-1, -1), radius)
	_draw_corner(Vector2(h.position.x, h.end.y), Vector2(1, -1), radius)
	draw_style_box(_ring_box, h)


## Fill the concave notch between the hole's square corner and its rounding arc, so the
## rectangular cutout reads as a rounded one. dir points from the corner into the hole.
func _draw_corner(corner: Vector2, dir: Vector2, radius: float) -> void:
	if radius <= 0.5:
		return
	var center := corner + dir * radius
	var pts := PackedVector2Array()
	pts.append(corner)
	for i in CORNER_SEGMENTS + 1:
		var a := (float(i) / float(CORNER_SEGMENTS)) * PI * 0.5
		pts.append(center + Vector2(-dir.x * cos(a), -dir.y * sin(a)) * radius)
	draw_colored_polygon(pts, DIM_COLOR)
