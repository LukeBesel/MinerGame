## StationPanel — the left production-line list: buy-multiplier toggle (x1/x10/x100/MAX)
## on top, then one StationCard per station (index-aligned with sim_stats.stations) in a
## ScrollContainer. Reacts to EventBus.station_selected (3D clicks) with highlight+scroll.
extends PanelContainer

const UiUtil = preload("res://src/ui/ui_util.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const StationCard = preload("res://src/ui/station_card.gd")
const TooltipScript = preload("res://src/ui/tooltip.gd")

const MULT_OPTIONS := [1, 10, 100, SimTypes.BUY_MAX]

var _tooltip = null
var _scroll: ScrollContainer
var _cards_box: VBoxContainer
var _cards: Array = []
var _mult_btns: Array = []
var _selected := -1
var _mult := 1


func setup(tooltip) -> void:
	_tooltip = tooltip


func _ready() -> void:
	name = "StationPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	# Buy-multiplier segmented toggle.
	var mult_row := HBoxContainer.new()
	mult_row.add_theme_constant_override("separation", 4)
	v.add_child(mult_row)
	var buy_label := Label.new()
	buy_label.theme_type_variation = "DimLabel"
	buy_label.text = L.t("ui.buy")
	buy_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mult_row.add_child(buy_label)
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
		mult_row.add_child(b)
		_mult_btns.append(b)
	if _tooltip != null:
		_tooltip.attach(mult_row, _tip_mult)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cards_box)

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.station_selected.connect(_on_station_selected)
	EventBus.buy_multiplier_changed.connect(_on_mult_changed)
	EventBus.game_reset.connect(_refresh_once)
	EventBus.load_completed.connect(_refresh_once)
	_sync_mult_from_game()
	_refresh_once()


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
	for i in stations.size():
		var view_v: Variant = stations[i]
		if typeof(view_v) != TYPE_DICTIONARY:
			continue
		var view: Dictionary = view_v
		var upviews := {}
		if bool(view.get("unlocked", false)):
			for uid in UiUtil.UPGRADE_IDS:
				upviews[uid] = UiUtil.upgrade_view(i, str(uid))
		var card: Variant = _cards[i]
		card.update_view(view, upviews, money)


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
