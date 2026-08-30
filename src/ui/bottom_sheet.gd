## BottomSheet — the MOBILE replacement for the left station column. Collapsed (~190
## design px): drag/tap handle with a stations count, the promoted bottleneck summary and
## the always-visible full-width FIX IT button. Expanded (~65% height, hud re-anchors):
## the existing StationPanel (reparented in via attach_station_list) with full-width
## cards; FIX IT stays pinned under the list, so collapsing never hides it. Tap the
## handle or swipe it vertically to toggle. Renders from EventBus.sim_stats.
extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")

signal sheet_toggled(expanded: bool)

const COLLAPSED_H := 190.0
const EXPANDED_FRAC := 0.65
const SWIPE_MIN := 24.0			# vertical drag beyond this = swipe, below = tap

var expanded := false

var _panel: PanelContainer
var _handle: PanelContainer
var _chevron: Label
var _count_label: Label
var _summary: HBoxContainer
var _sum_glyph: Label
var _sum_name: Label
var _sum_status: Label
var _sum_thr: Label
var _list_slot: VBoxContainer
var _fix_btn: Button

var _fix: Dictionary = {}
var _bn_index := -1
var _drag_from_y := 0.0
var _drag_dy := 0.0
var _dragging := false


func _ready() -> void:
	name = "BottomSheet"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.theme_type_variation = "SheetPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UiUtil.full_rect(_panel)
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)

	# Handle: tap or swipe toggles; keyboard ui_accept too.
	_handle = PanelContainer.new()
	_handle.theme_type_variation = "SheetHandle"
	_handle.custom_minimum_size = Vector2(0, UiTheme.TOUCH_MIN_MOBILE)
	_handle.focus_mode = Control.FOCUS_ALL
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_handle.gui_input.connect(_on_handle_input)
	v.add_child(_handle)
	var handle_row := HBoxContainer.new()
	handle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	handle_row.add_theme_constant_override("separation", 8)
	_handle.add_child(handle_row)
	_chevron = Label.new()
	_chevron.theme_type_variation = "GlyphLabel"
	_chevron.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
	_chevron.text = "▲"
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	handle_row.add_child(_chevron)
	_count_label = Label.new()
	_count_label.theme_type_variation = "DimLabel"
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	handle_row.add_child(_count_label)

	# Collapsed summary: the current bottleneck at a glance.
	_summary = HBoxContainer.new()
	_summary.add_theme_constant_override("separation", 8)
	v.add_child(_summary)
	_sum_glyph = Label.new()
	_sum_glyph.theme_type_variation = "GlyphLabel"
	_sum_glyph.text = "○"
	_sum_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_summary.add_child(_sum_glyph)
	_sum_name = Label.new()
	_sum_name.theme_type_variation = "TitleLabel"
	_sum_name.clip_text = true
	_sum_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sum_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sum_name.text = "—"
	_summary.add_child(_sum_name)
	_sum_status = Label.new()
	_sum_status.theme_type_variation = "DimLabel"
	_sum_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_summary.add_child(_sum_status)
	_sum_thr = Label.new()
	_sum_thr.theme_type_variation = "ValueLabel"
	_sum_thr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_summary.add_child(_sum_thr)

	# Expanded: the reparented StationPanel lives here (attach_station_list).
	_list_slot = VBoxContainer.new()
	_list_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_slot.visible = false
	v.add_child(_list_slot)

	# The persistent FIX IT call-to-action (never hidden by collapsing).
	_fix_btn = Button.new()
	_fix_btn.theme_type_variation = "FixButton"
	_fix_btn.custom_minimum_size = Vector2(0, 56.0)
	_fix_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fix_btn.visible = false
	_fix_btn.pressed.connect(_on_fix_pressed)
	v.add_child(_fix_btn)

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.game_reset.connect(_refresh_once)
	EventBus.load_completed.connect(_refresh_once)
	_apply_state()
	_refresh_once()


# ---------------------------------------------------------------- hud API

## The sheet's height for a given design-space height (hud anchors the sheet with this).
func current_height(design_h: float) -> float:
	return design_h * EXPANDED_FRAC if expanded else COLLAPSED_H


## Reparent the existing StationPanel into the expanded list slot.
func attach_station_list(panel: Control) -> void:
	if panel == null:
		return
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_slot.add_child(panel)


## Remove the StationPanel from the sheet again (hud reparents it back for DESKTOP).
func detach_station_list(panel: Control) -> void:
	if panel != null and panel.get_parent() == _list_slot:
		_list_slot.remove_child(panel)


func set_expanded(v: bool) -> void:
	if expanded == v:
		return
	expanded = v
	_apply_state()
	sheet_toggled.emit(expanded)


## Global rect of the sheet's FIX IT button — the MOBILE "fix_button" onboarding target.
func fix_button_rect() -> Rect2:
	if _fix_btn != null and _fix_btn.visible and _fix_btn.is_visible_in_tree():
		return _fix_btn.get_global_rect()
	return Rect2()


## Global rect of the bottleneck summary (MOBILE "bottleneck_card" fallback target).
func summary_rect() -> Rect2:
	if _summary != null and _summary.visible and _summary.is_visible_in_tree():
		return _summary.get_global_rect()
	if _panel != null and _panel.is_visible_in_tree():
		return _panel.get_global_rect()
	return Rect2()


# ---------------------------------------------------------------- state / input

func _apply_state() -> void:
	if _chevron == null:
		return
	_chevron.text = "▼" if expanded else "▲"
	_summary.visible = not expanded
	_list_slot.visible = expanded


func _on_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_dragging = true
			_drag_from_y = mb.global_position.y
			_drag_dy = 0.0
		elif _dragging:
			_dragging = false
			_finish_gesture()
		_handle.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_dy = (event as InputEventMouseMotion).global_position.y - _drag_from_y
	elif event is InputEventScreenDrag and _dragging:
		_drag_dy = (event as InputEventScreenDrag).position.y - _drag_from_y
	elif event.is_action_pressed("ui_accept"):
		set_expanded(not expanded)
		_handle.accept_event()


## Tap toggles; a decisive vertical swipe picks its direction explicitly.
func _finish_gesture() -> void:
	if absf(_drag_dy) < SWIPE_MIN:
		set_expanded(not expanded)
	else:
		set_expanded(_drag_dy < 0.0)
	if AudioDirector.has_method("play"):
		AudioDirector.play("tab")


# ---------------------------------------------------------------- 10 Hz render

func _refresh_once() -> void:
	var stats := UiUtil.stats_snapshot()
	if not stats.is_empty():
		_on_sim_stats(stats)


func _on_sim_stats(stats: Dictionary) -> void:
	if not is_visible_in_tree():
		return
	var stations_v: Variant = stats.get("stations", [])
	var stations: Array = stations_v if typeof(stations_v) == TYPE_ARRAY else []
	UiUtil.set_label(_count_label, UiUtil.trf_or("ui.sheet_stations", [stations.size()], "▦ " + str(stations.size())))
	_bn_index = int(stats.get("bottleneck", -1))
	var view: Dictionary = {}
	if _bn_index >= 0 and _bn_index < stations.size() and typeof(stations[_bn_index]) == TYPE_DICTIONARY:
		view = stations[_bn_index]
	_update_summary(view)
	_fix = UiUtil.best_fix_view() if _bn_index >= 0 else {}
	_update_fix_btn()


func _update_summary(view: Dictionary) -> void:
	if view.is_empty():
		UiUtil.set_label(_sum_glyph, "●")
		_sum_glyph.add_theme_color_override("font_color", UiTheme.COL_GREEN)
		UiUtil.set_label(_sum_name, "—")
		UiUtil.set_label(_sum_status, "")
		UiUtil.set_label(_sum_thr, "")
		return
	var status := int(view.get("status", -1))
	UiUtil.set_label(_sum_glyph, UiUtil.status_glyph(status, true))
	_sum_glyph.add_theme_color_override("font_color", UiUtil.status_color(status, true))
	UiUtil.set_label(_sum_name, str(view.get("name", "")))
	_sum_name.add_theme_color_override("font_color", UiTheme.COL_RED)
	UiUtil.set_label(_sum_status, UiUtil.status_name(status, true))
	UiUtil.set_label(_sum_thr, UiUtil.per_sec(view.get("throughput", 0.0)))


## Mirror of the station card's FIX IT labeling (ui.fix_it / ui.fix_unlock /
## ui.fix_saving formatted with the cost + the view's localized label as line 2).
func _update_fix_btn() -> void:
	if _fix.is_empty():
		_fix_btn.visible = false
		return
	_fix_btn.visible = true
	var affordable := bool(_fix.get("affordable", false))
	var key := UiUtil.fix_label_key(str(_fix.get("kind", "")), affordable)
	var text := UiUtil.trf(key, [UiUtil.money(_fix.get("cost"))])
	var detail := str(_fix.get("label", ""))
	if detail != "":
		text += "\n" + detail
	UiUtil.set_btn(_fix_btn, text)
	_fix_btn.disabled = not affordable


func _on_fix_pressed() -> void:
	if not UiUtil.game_ready():
		return
	if UiUtil.game_cmd("apply_best_fix"):
		if Juice.has_method("squash"):
			Juice.squash(_fix_btn)
		if AudioDirector.has_method("play"):
			AudioDirector.play("click")
	elif AudioDirector.has_method("play"):
		AudioDirector.play("error")
