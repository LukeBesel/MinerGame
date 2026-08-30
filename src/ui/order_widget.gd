## OrderWidget — compact rush-order bar under the Coach. Hidden by default; slides in on
## EventBus.order_started, renders name/progress/countdown/bonus from the "order" dict in
## sim_stats (polling Game.get_order_view() as fallback), green-flashes + toasts on
## order_completed, gently toasts on order_failed. Guards duplicate signals and survives
## game_reset. All motion honors reduce_motion (instant show/hide).
extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")

const STATE_HIDDEN := 0
const STATE_ACTIVE := 1
const STATE_LEAVING := 2

const FLASH_HOLD_S := 0.7		# how long the green "shipped!" state lingers
const SLIDE_S := 0.25
const BAR_MIN_W := 140.0
const TIME_WARN_S := 10.0

var _panel: PanelContainer
var _title: Label
var _bar: ProgressBar
var _progress: Label
var _time: Label
var _reward: Label

var _state := STATE_HIDDEN
var _active_id := ""
var _seen_data := false			# saw at least one non-empty order dict this run
var _tween: Tween = null


# ---------------------------------------------------------------- pure helpers (tested)

## Progress bar ratio; a degenerate required <= 0 counts as complete.
static func order_ratio(progress: float, required: float) -> float:
	if required <= 0.0:
		return 1.0
	return clampf(progress / required, 0.0, 1.0)


## Whole-seconds countdown text (ceil, never negative): 0.2 -> "1", -3 -> "0".
static func seconds_left_str(seconds: float) -> String:
	return str(int(ceilf(maxf(seconds, 0.0))))


## ["current","required"] display pair for ui.order_progress — current floored and never
## shown above the requirement.
static func progress_pair(progress: float, required: float) -> Array:
	var req := maxf(required, 0.0)
	var cur := floorf(maxf(progress, 0.0))
	if req > 0.0:
		cur = minf(cur, req)
	return [UiUtil.trim_float(cur), UiUtil.trim_float(req)]


# ---------------------------------------------------------------- build

func _ready() -> void:
	name = "OrderWidget"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.name = "OrderPanel"
	_panel.theme_type_variation = "OrderPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	add_child(_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_panel.add_child(h)

	var glyph := Label.new()
	glyph.theme_type_variation = "GlyphLabel"
	glyph.add_theme_color_override("font_color", UiTheme.COL_AMBER)
	glyph.text = "⚑"
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(glyph)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 3)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	_title = Label.new()
	_title.theme_type_variation = "ValueLabel"
	_title.clip_text = true
	mid.add_child(_title)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	mid.add_child(bar_row)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(BAR_MIN_W, 10)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_bar)
	_progress = Label.new()
	_progress.theme_type_variation = "TinyLabel"
	bar_row.add_child(_progress)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	h.add_child(right)
	_time = Label.new()
	_time.theme_type_variation = "ValueLabel"
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_time)
	_reward = Label.new()
	_reward.theme_type_variation = "TinyLabel"
	_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_reward)

	EventBus.order_started.connect(_on_order_started)
	EventBus.order_completed.connect(_on_order_completed)
	EventBus.order_failed.connect(_on_order_failed)
	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.game_reset.connect(_hide_now)


# ---------------------------------------------------------------- signals / state machine

func _on_order_started(order_id: String) -> void:
	if _state == STATE_ACTIVE and _active_id == order_id:
		return	# duplicate start
	_active_id = order_id
	_seen_data = false
	_begin_show(false)
	var d := UiUtil.order_view()
	if not d.is_empty():
		_seen_data = true
		_render(d)


func _on_order_completed(order_id: String, reward: Variant) -> void:
	if _state != STATE_ACTIVE:
		return	# duplicate/stale completion
	if _active_id != "" and order_id != _active_id:
		return
	EventBus.request_toast.emit(UiUtil.trf("ui.order_done", [UiUtil.fmt(reward)]))
	_leave(true)


func _on_order_failed(order_id: String) -> void:
	if _state != STATE_ACTIVE:
		return
	if _active_id != "" and order_id != _active_id:
		return
	EventBus.request_toast.emit(L.t("ui.order_missed"))
	_leave(false)


func _on_sim_stats(stats: Dictionary) -> void:
	var d: Dictionary = {}
	var ov: Variant = stats.get("order")
	if typeof(ov) == TYPE_DICTIONARY:
		d = ov
	if _state == STATE_ACTIVE:
		if d.is_empty():
			d = UiUtil.order_view()	# fallback until snapshots carry "order"
		if not d.is_empty():
			_seen_data = true
			_render(d)
		elif _seen_data:
			_hide_now()	# order vanished without its signal (reset edge)
	elif _state == STATE_HIDDEN and not d.is_empty():
		# Loaded/booted into a running order — appear without animation.
		_active_id = str(d.get("id", ""))
		_begin_show(true)
		_seen_data = true
		_render(d)


# ---------------------------------------------------------------- render

func _render(d: Dictionary) -> void:
	var order_name := str(d.get("name", ""))
	if order_name == "":
		var nk := str(d.get("name_key", ""))
		if nk != "":
			order_name = UiUtil.tr_key(nk)
	var title := L.t("ui.order_title")
	if order_name != "":
		title += " · " + order_name
	UiUtil.set_label(_title, title)
	var required := float(d.get("required", 0.0))
	var progress := float(d.get("progress", 0.0))
	_bar.value = order_ratio(progress, required)
	UiUtil.set_label(_progress, UiUtil.trf("ui.order_progress", progress_pair(progress, required)))
	var secs := float(d.get("seconds_left", 0.0))
	UiUtil.set_label(_time, UiUtil.trf("ui.order_time_left", [seconds_left_str(secs)]))
	_time.add_theme_color_override("font_color",
			UiTheme.COL_RED if secs < TIME_WARN_S else UiTheme.COL_TEXT)
	UiUtil.set_label(_reward, UiUtil.trf("ui.order_reward",
			[UiUtil.trim_float(float(d.get("reward_mult", 1.0)))]))
	_panel.reset_size()
	_panel.position.x = -_panel.size.x * 0.5	# y belongs to the slide tween


func _begin_show(instant: bool) -> void:
	_kill_tween()
	_state = STATE_ACTIVE
	_panel.theme_type_variation = "OrderPanel"
	_panel.visible = true
	_panel.reset_size()
	_panel.position = Vector2(-_panel.size.x * 0.5, 0.0)
	if instant or UiUtil.reduce_motion():
		_panel.modulate = Color(1, 1, 1, 1)
		return
	_panel.modulate = Color(1, 1, 1, 0)
	_panel.position.y = -14.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, SLIDE_S).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_panel, "position:y", 0.0, SLIDE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _leave(flash_good: bool) -> void:
	_state = STATE_LEAVING
	_active_id = ""
	_seen_data = false
	_kill_tween()
	if flash_good:
		_panel.theme_type_variation = "OrderPanelGood"
		_bar.value = 1.0
	if UiUtil.reduce_motion():
		if flash_good:
			# The flash is a color state, not motion: hold it briefly, then hide.
			_tween = create_tween()
			_tween.tween_interval(FLASH_HOLD_S)
			_tween.tween_callback(_hide_now)
		else:
			_hide_now()
		return
	_tween = create_tween()
	if flash_good:
		_tween.tween_interval(FLASH_HOLD_S)
	_tween.tween_property(_panel, "modulate:a", 0.0, SLIDE_S + 0.05).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(_panel, "position:y", -14.0, SLIDE_S + 0.05) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_hide_now)


func _hide_now() -> void:
	_kill_tween()
	_state = STATE_HIDDEN
	_active_id = ""
	_seen_data = false
	if _panel != null:
		_panel.visible = false
		_panel.modulate = Color(1, 1, 1, 1)
		_panel.theme_type_variation = "OrderPanel"


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
