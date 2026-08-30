## Coach — the Andon board: evaluates Data.db.hints against sim_stats with internal timers
## and shows ONE highest-priority hint at a time (higher "priority" int wins; ties → first
## in file order). Pure evaluation lives in static funcs so tests can exercise it headless.
extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")

const MIN_SHOW_S := 3.0			# a shown hint holds the board at least this long
const STALE_HIDE_S := 4.0		# hide once the condition has been false this long
const MAX_TEXT_W := 520.0
const DEFAULT_COOLDOWN_S := 30.0

const HIDDEN_TARGET_SIZE := Vector2(360.0, 52.0)	# synthetic onboarding rect while hidden

var _panel: PanelContainer
var _text: Label
var _targets = null
var _suppressed := false		# onboarding overlay up: don't evaluate/show hints


func setup(targets = null) -> void:
	_targets = targets

var _starved_s: Dictionary = {}		# station index -> seconds continuously starved
var _bn_index := -1
var _bn_stuck_s := 0.0
var _affordable_bn_upgrade := false
var _skill_affordable := false
var _can_prestige := false
var _kp := 0.0

var _cooldowns: Dictionary = {}		# hint id -> unix-ish seconds when it may show again
var _current: Dictionary = {}
var _shown_at := 0.0
var _false_since := -1.0
var _last_tick_ms := 0
var _throttle_a := 0.0
var _throttle_b := 0.0


# ---------------------------------------------------------------- pure evaluation

## Evaluate one hints.json condition against a precomputed context dictionary.
## ctx keys: max_starved_s, bottleneck_stuck_s, affordable_bottleneck_upgrade,
## kp, skill_affordable, can_prestige.
static func eval_condition(cond: Dictionary, ctx: Dictionary) -> bool:
	var t := str(cond.get("type", ""))
	var value: Variant = cond.get("value", 0)
	match t:
		"always":
			return true
		"station_starved_seconds":
			return float(ctx.get("max_starved_s", 0.0)) >= float(value)
		"bottleneck_stuck_seconds":
			return float(ctx.get("bottleneck_stuck_s", 0.0)) >= float(value)
		"affordable_bottleneck_upgrade":
			return bool(ctx.get("affordable_bottleneck_upgrade", false))
		"kp_unspent":
			return float(ctx.get("kp", 0.0)) >= float(value) and bool(ctx.get("skill_affordable", false))
		"can_prestige":
			return bool(ctx.get("can_prestige", false))
	return false


## Pick the winning hint: condition true, off cooldown, highest priority (ties → first).
## Returns {} when nothing qualifies.
static func pick_hint(hints: Array, ctx: Dictionary, cooldowns: Dictionary, now: float) -> Dictionary:
	var best: Dictionary = {}
	var best_priority := -2147483648
	for h in hints:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var hd: Dictionary = h
		var hid := str(hd.get("id", ""))
		if hid == "" or now < float(cooldowns.get(hid, 0.0)):
			continue
		var cond: Variant = hd.get("cond", {})
		if typeof(cond) != TYPE_DICTIONARY or not eval_condition(cond, ctx):
			continue
		var priority := int(hd.get("priority", 0))
		if priority > best_priority:
			best_priority = priority
			best = hd
	return best


# ---------------------------------------------------------------- runtime

func _ready() -> void:
	name = "Coach"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.name = "AndonPanel"
	_panel.theme_type_variation = "CoachPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.visible = false
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_panel.add_child(h)
	var lamp := Label.new()
	lamp.theme_type_variation = "GlyphLabel"
	lamp.add_theme_color_override("font_color", UiTheme.COL_AMBER)
	lamp.text = "●"
	lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lamp)
	_text = Label.new()
	_text.theme_type_variation = "Label"
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_text)
	var close := Label.new()
	close.theme_type_variation = "TinyLabel"
	close.text = "×"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(close)

	if _targets != null and _targets.has_method("register"):
		_targets.register("coach", _target_rect)

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.game_reset.connect(_on_game_reset)


## Onboarding target: the visible Andon panel, or (it is suppressed while the overlay is
## up) a synthetic rect centered on the board's anchor point so the step still points here.
func _target_rect() -> Rect2:
	if _panel != null and _panel.visible and _panel.is_visible_in_tree():
		return _panel.get_global_rect()
	if is_inside_tree():
		return Rect2(global_position - Vector2(HIDDEN_TARGET_SIZE.x * 0.5, 0.0), HIDDEN_TARGET_SIZE)
	return Rect2()


## While suppressed (onboarding overlay) the coach neither evaluates nor shows hints.
func set_suppressed(on: bool) -> void:
	if _suppressed == on:
		return
	_suppressed = on
	if on:
		_hide_now()


func _on_game_reset() -> void:
	_starved_s.clear()
	_bn_index = -1
	_bn_stuck_s = 0.0
	_affordable_bn_upgrade = false
	_can_prestige = false
	_hide_now()


func _on_sim_stats(stats: Dictionary) -> void:
	var now_ms := Time.get_ticks_msec()
	var dt := clampf(float(now_ms - _last_tick_ms) / 1000.0, 0.0, 1.0)
	_last_tick_ms = now_ms
	if _suppressed:
		return	# timestamp still advanced so timers don't jump on release
	_update_timers(stats, dt)
	_update_throttled(stats, dt)
	_drive_board(stats)


func _update_timers(stats: Dictionary, dt: float) -> void:
	var stations: Variant = stats.get("stations", [])
	if typeof(stations) == TYPE_ARRAY:
		for view in stations:
			if typeof(view) != TYPE_DICTIONARY:
				continue
			var vd: Dictionary = view
			var idx := int(vd.get("index", -1))
			if idx < 0:
				continue
			var starving: bool = bool(vd.get("unlocked", false)) and int(vd.get("status", -1)) == SimTypes.STATUS_STARVED
			_starved_s[idx] = (float(_starved_s.get(idx, 0.0)) + dt) if starving else 0.0
	var bn := int(stats.get("bottleneck", -1))
	if bn != _bn_index:
		_bn_index = bn
		_bn_stuck_s = 0.0
	elif bn >= 0:
		_bn_stuck_s += dt
	_kp = float(stats.get("kp", 0.0))


func _update_throttled(stats: Dictionary, dt: float) -> void:
	_throttle_a -= dt
	if _throttle_a <= 0.0:
		_throttle_a = 0.5
		_affordable_bn_upgrade = false
		var bn := int(stats.get("bottleneck", -1))
		if bn >= 0 and UiUtil.game_ready():
			for uid in UiUtil.UPGRADE_IDS:
				var uv := UiUtil.upgrade_view(bn, str(uid))
				if bool(uv.get("affordable", false)) and not bool(uv.get("maxed", false)):
					_affordable_bn_upgrade = true
					break
	_throttle_b -= dt
	if _throttle_b <= 0.0:
		_throttle_b = 1.0
		_can_prestige = bool(UiUtil.prestige_view().get("can_prestige", false))
		_skill_affordable = false
		if UiUtil.game_ready():
			for node in UiUtil.db_list("skills"):
				if typeof(node) != TYPE_DICTIONARY:
					continue
				var st := UiUtil.skill_state(str((node as Dictionary).get("id", "")))
				if bool(st.get("available", false)) and bool(st.get("affordable", false)) and not bool(st.get("purchased", false)):
					_skill_affordable = true
					break


func _context() -> Dictionary:
	var max_starved := 0.0
	for k in _starved_s:
		max_starved = maxf(max_starved, float(_starved_s[k]))
	return {
		"max_starved_s": max_starved,
		"bottleneck_stuck_s": _bn_stuck_s,
		"affordable_bottleneck_upgrade": _affordable_bn_upgrade,
		"kp": _kp,
		"skill_affordable": _skill_affordable,
		"can_prestige": _can_prestige,
	}


func _drive_board(_stats: Dictionary) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	var ctx := _context()

	if not _current.is_empty():
		var cond: Variant = _current.get("cond", {})
		var still_true: bool = typeof(cond) == TYPE_DICTIONARY and eval_condition(cond, ctx)
		if still_true:
			_false_since = -1.0
		elif _false_since < 0.0:
			_false_since = now
		elif now - _false_since >= STALE_HIDE_S:
			_hide_now()

	var candidate := pick_hint(UiUtil.db_list("hints"), ctx, _cooldowns, now)
	if candidate.is_empty():
		return
	if _current.is_empty():
		_show(candidate, now)
	elif str(candidate.get("id", "")) != str(_current.get("id", "")) \
			and int(candidate.get("priority", 0)) > int(_current.get("priority", 0)) \
			and now - _shown_at >= MIN_SHOW_S:
		_show(candidate, now)


func _show(hint: Dictionary, now: float) -> void:
	var text := L.t(str(hint.get("text_key", "")))
	_current = hint
	_shown_at = now
	_false_since = -1.0
	_cooldowns[str(hint.get("id", ""))] = now + float(hint.get("cooldown_s", DEFAULT_COOLDOWN_S))
	UiUtil.set_label(_text, text)
	UiUtil.fit_label(_text, MAX_TEXT_W)
	_panel.visible = true
	_panel.reset_size()
	_panel.position = Vector2(-_panel.size.x * 0.5, 0.0)
	if not UiUtil.reduce_motion():
		_panel.modulate = Color(1, 1, 1, 0)
		var from_y := -14.0
		_panel.position.y = from_y
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_panel, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_panel.modulate = Color(1, 1, 1, 1)
	EventBus.coach_hint.emit(text)


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_dismiss()
			accept_event()


func _dismiss() -> void:
	if _current.is_empty():
		_hide_now()
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	_cooldowns[str(_current.get("id", ""))] = now + float(_current.get("cooldown_s", DEFAULT_COOLDOWN_S))
	_hide_now()


func _hide_now() -> void:
	_current = {}
	_false_since = -1.0
	_panel.visible = false
