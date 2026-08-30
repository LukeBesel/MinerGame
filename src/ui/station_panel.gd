## StationPanel — the left production-line list: ui-mode toggle (simple/advanced) and the
## buy-multiplier toggle (x1/x10/x100/MAX, advanced only) on top, then one StationCard per
## station (index-aligned with sim_stats.stations) in a ScrollContainer. Reacts to
## EventBus.station_selected (3D clicks) with highlight+scroll; owns the simple-mode
## best-fix plumbing and the bottleneck_card / fix_button onboarding targets.
extends PanelContainer

const UiUtil = preload("res://src/ui/ui_util.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const StationCard = preload("res://src/ui/station_card.gd")
const TooltipScript = preload("res://src/ui/tooltip.gd")

const MULT_OPTIONS := [1, 10, 100, SimTypes.BUY_MAX]
const TOGGLE_MIN_H := 44.0		# simple-mode target floor

var _tooltip = null
var _targets = null
var _scroll: ScrollContainer
var _cards_box: VBoxContainer
var _cards: Array = []
var _mult_btns: Array = []
var _mult_row: HBoxContainer
var _mode_btn: Button
var _selected := -1
var _mult := 1
var _ui_mode := "simple"
var _bn_index := -1


func setup(tooltip, targets = null) -> void:
	_tooltip = tooltip
	_targets = targets


func _ready() -> void:
	name = "StationPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	# Mode toggle: the button names the mode you switch TO.
	var mode_row := HBoxContainer.new()
	v.add_child(mode_row)
	var mode_spacer := Control.new()
	mode_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_row.add_child(mode_spacer)
	_mode_btn = Button.new()
	_mode_btn.theme_type_variation = "GhostButton"
	UiUtil.min_touch(_mode_btn, 96.0)
	_mode_btn.custom_minimum_size.y = TOGGLE_MIN_H
	_mode_btn.pressed.connect(_on_mode_toggle)
	mode_row.add_child(_mode_btn)

	# Buy-multiplier segmented toggle (advanced mode only).
	_mult_row = HBoxContainer.new()
	_mult_row.add_theme_constant_override("separation", 4)
	v.add_child(_mult_row)
	var buy_label := Label.new()
	buy_label.theme_type_variation = "DimLabel"
	buy_label.text = L.t("ui.buy")
	buy_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mult_row.add_child(buy_label)
	for m in MULT_OPTIONS:
		var b := Button.new()
		b.theme_type_variation = "MultButton"
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiUtil.min_touch(b)
		var mi := int(m)
		if mi == SimTypes.BUY_MAX:
			b.text = UiUtil.trf_or("ui.buy_mult_max", [], L.t("ui.max"))
		else:
			b.text = UiUtil.trf_or("ui.buy_mult_" + str(mi), [], "x" + str(mi))
		b.pressed.connect(_on_mult_pressed.bind(mi))
		_mult_row.add_child(b)
		_mult_btns.append(b)
	if _tooltip != null:
		_tooltip.attach(_mult_row, _tip_mult)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cards_box)

	if _targets != null and _targets.has_method("register"):
		_targets.register("bottleneck_card", _target_bottleneck_card)
		_targets.register("fix_button", _target_fix_button)

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.station_selected.connect(_on_station_selected)
	EventBus.buy_multiplier_changed.connect(_on_mult_changed)
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.game_reset.connect(_refresh_once)
	EventBus.load_completed.connect(_refresh_once)
	_sync_mult_from_game()
	_apply_ui_mode(UiUtil.ui_mode())
	_refresh_once()


# ---------------------------------------------------------------- ui mode

func _on_mode_toggle() -> void:
	var next_mode := "advanced" if _ui_mode != "advanced" else "simple"
	if not UiUtil.write_setting("ui_mode", next_mode):
		# Field not shipped yet: keep the flip session-local, announce it ourselves so
		# every listener (this panel included) re-renders through the same path.
		EventBus.settings_changed.emit("ui_mode", next_mode)
	if AudioDirector.has_method("play"):
		AudioDirector.play("click")


func _on_settings_changed(key: String, value: Variant) -> void:
	if key == "ui_mode":
		_apply_ui_mode(UiUtil.resolve_ui_mode(value))


func _apply_ui_mode(mode: String) -> void:
	_ui_mode = mode
	var advanced := mode == "advanced"
	if _mode_btn != null:
		UiUtil.set_btn(_mode_btn, L.t("ui.simple_toggle" if advanced else "ui.advanced_toggle"))
	if _mult_row != null:
		_mult_row.visible = advanced
	for card in _cards:
		if is_instance_valid(card):
			card.set_ui_mode(mode)
	_rerender()


## Re-render from the last snapshot without touching the selection (mode flips).
func _rerender() -> void:
	var stats := UiUtil.stats_snapshot()
	if not stats.is_empty():
		_on_sim_stats(stats)


# ---------------------------------------------------------------- onboarding targets

func _bn_card() -> Variant:
	if _bn_index >= 0 and _bn_index < _cards.size():
		var card: Variant = _cards[_bn_index]
		if is_instance_valid(card):
			return card
	return null


func _target_bottleneck_card() -> Rect2:
	var card: Variant = _bn_card()
	if card != null and card.is_visible_in_tree():
		return card.get_global_rect()
	return Rect2()


func _target_fix_button() -> Rect2:
	var card: Variant = _bn_card()
	if card != null and card.has_method("fix_button_rect"):
		return card.fix_button_rect()
	return Rect2()


func _tip_mult() -> Array:
	return [
		TooltipScript.title_row(L.t("ui.buy")),
		TooltipScript.dim_row(L.t("ui.tip_buy_mult")),
	]


func _refresh_once() -> void:
	_selected = -1
	var stats := UiUtil.stats_snapshot()
	if not stats.is_empty():
		_on_sim_stats(stats)
	_apply_selection()


func _sync_mult_from_game() -> void:
	var g := UiUtil.autoload("Game")
	if g != null and ("buy_multiplier" in g):
		var m: Variant = g.get("buy_multiplier")
		if typeof(m) == TYPE_INT:
			_mult = int(m)
	_apply_mult_buttons()


func _on_mult_pressed(m: int) -> void:
	_mult = m
	_apply_mult_buttons()
	if UiUtil.game_ready():
		UiUtil.game_call("set_buy_multiplier", [m])
	if AudioDirector.has_method("play"):
		AudioDirector.play("click")


func _on_mult_changed(m: int) -> void:
	_mult = m
	_apply_mult_buttons()


func _apply_mult_buttons() -> void:
	for i in _mult_btns.size():
		var b: Button = _mult_btns[i]
		b.set_pressed_no_signal(int(MULT_OPTIONS[i]) == _mult)


# ---------------------------------------------------------------- 10 Hz render

func _on_sim_stats(stats: Dictionary) -> void:
	var stations_v: Variant = stats.get("stations", [])
	if typeof(stations_v) != TYPE_ARRAY:
		return
	var stations: Array = stations_v
	_ensure_cards(stations.size())
	var money: Variant = stats.get("money")
	_bn_index = int(stats.get("bottleneck", -1))
	var advanced := _ui_mode == "advanced"
	var fix: Dictionary = {}
	if not advanced and _bn_index >= 0:
		fix = UiUtil.best_fix_view()	# once per tick; keeps the FIX IT label fresh
	for i in stations.size():
		var view_v: Variant = stations[i]
		if typeof(view_v) != TYPE_DICTIONARY:
			continue
		var view: Dictionary = view_v
		var upviews := {}
		if advanced and bool(view.get("unlocked", false)):
			for uid in UiUtil.UPGRADE_IDS:
				upviews[uid] = UiUtil.upgrade_view(i, str(uid))
		var card: Variant = _cards[i]
		card.update_view(view, upviews, money, fix if i == _bn_index else {})


func _ensure_cards(n: int) -> void:
	if _cards.size() == n:
		return
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()
	for i in n:
		var card = StationCard.new()
		card.setup(i, _tooltip)
		card.set_ui_mode(_ui_mode)
		_cards_box.add_child(card)
		_cards.append(card)
	_apply_selection()


# ---------------------------------------------------------------- selection

func _on_station_selected(station: int) -> void:
	_selected = station
	_apply_selection()
	if station >= 0 and station < _cards.size():
		var card: Variant = _cards[station]
		if is_instance_valid(card):
			_scroll.ensure_control_visible(card)


func _apply_selection() -> void:
	for i in _cards.size():
		var card: Variant = _cards[i]
		if is_instance_valid(card):
			card.set_selected(i == _selected)
