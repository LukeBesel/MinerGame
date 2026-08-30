## TopBar — full-width strip: money (tween-counted), parts/sec, OEE, current
## bottleneck (named + "!" icon, clickable), and Kaizen Points. Renders from
## EventBus.sim_stats only; never polls the sim per frame. Two layouts: DESKTOP is the
## classic one-row strip; MOBILE stacks a compact money/pps/KP row over a slim
## OEE + full-width bottleneck chip row (hud.gd drives set_layout_mode).
extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const Layout = preload("res://src/ui/layout.gd")
const TooltipScript = preload("res://src/ui/tooltip.gd")

const MONEY_SIZE_SIMPLE := 26	# simple mode bumps the key numeral (≥ 26 px)
const MONEY_SIZE_MOBILE := 30	# mobile headline money

var _tooltip = null
var _targets = null

var _money_value: Label
var _money_box: Control
var _pps_box: Control
var _pps_value: Label
var _oee_box: Control
var _oee_value: Label
var _bn_chip: PanelContainer
var _bn_glyph: Label
var _bn_value: Label
var _kp_box: Control
var _kp_value: Label
var _row1: HBoxContainer
var _row2: HBoxContainer
var _spacer: Control

var _layout_mode := Layout.MODE_DESKTOP
var _bn_index := -1
var _last_money = null			# BigNum of the last rendered tick
var _countup_hold := 0.0		# seconds left where Juice.count_up owns the label
var _last_tick_ms := 0


func setup(tooltip, targets = null) -> void:
	_tooltip = tooltip
	_targets = targets


func _ready() -> void:
	name = "TopBar"
	theme_type_variation = "TopBarPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	add_child(rows)
	_row1 = HBoxContainer.new()
	_row1.add_theme_constant_override("separation", 22)
	rows.add_child(_row1)
	_row2 = HBoxContainer.new()
	_row2.add_theme_constant_override("separation", 10)
	_row2.visible = false
	rows.add_child(_row2)

	var money_block := _make_block("ui.money", "ui.tip_money")
	_money_box = money_block["box"]
	_money_value = money_block["value"]
	_money_value.theme_type_variation = "MoneyLabel"

	var pps_block := _make_block("ui.parts_per_sec", "ui.tip_pps")
	_pps_box = pps_block["box"]
	_pps_value = pps_block["value"]

	var oee_block := _make_block("ui.oee", "ui.tip_oee")
	_oee_box = oee_block["box"]
	_oee_value = oee_block["value"]

	_spacer = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bn_chip = _make_bottleneck_chip()

	var kp_block := _make_glyph_block("◆", UiTheme.COL_AMBER, "ui.kaizen_points", "ui.tip_kp")
	_kp_box = kp_block["box"]
	_kp_value = kp_block["value"]

	_arrange_rows()

	if _targets != null and _targets.has_method("register"):
		_targets.register("top_bar_money", _target_money)

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.game_reset.connect(_on_game_reset)
	EventBus.load_completed.connect(_refresh_once)
	EventBus.settings_changed.connect(_on_settings_changed)
	_apply_money_size(UiUtil.ui_mode())
	_refresh_once()


## hud.gd: switch between the one-row DESKTOP strip and the two-row MOBILE bar.
func set_layout_mode(mode: int) -> void:
	if _layout_mode == mode:
		return
	_layout_mode = mode
	if _row1 != null:
		_arrange_rows()
		_apply_money_size(UiUtil.ui_mode())


## Distribute the stat blocks over the rows for the current layout mode.
func _arrange_rows() -> void:
	var mobile := _layout_mode == Layout.MODE_MOBILE
	for block in [_money_box, _pps_box, _oee_box, _spacer, _bn_chip, _kp_box]:
		var c := block as Control
		if c != null and c.get_parent() != null:
			c.get_parent().remove_child(c)
	if mobile:
		for c in [_money_box, _spacer, _pps_box, _kp_box]:
			_row1.add_child(c)
		for c in [_oee_box, _bn_chip]:
			_row2.add_child(c)
		_bn_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bn_chip.custom_minimum_size.y = UiTheme.TOUCH_MIN_MOBILE
	else:
		for c in [_money_box, _pps_box, _oee_box, _spacer, _bn_chip, _kp_box]:
			_row1.add_child(c)
		_bn_chip.size_flags_horizontal = Control.SIZE_FILL
		_bn_chip.custom_minimum_size.y = 0.0
	_row2.visible = mobile


func _target_money() -> Rect2:
	if _money_box != null and _money_box.is_visible_in_tree():
		return _money_box.get_global_rect()
	return Rect2()


## Simple mode bumps the headline money numeral to ≥ 26 px (mode is the resolved string);
## the MOBILE layout bumps it further regardless of ui_mode.
func _apply_money_size(mode: String) -> void:
	if _money_value == null:
		return
	if _layout_mode == Layout.MODE_MOBILE:
		_money_value.add_theme_font_size_override("font_size", MONEY_SIZE_MOBILE)
	elif mode == "advanced":
		_money_value.remove_theme_font_size_override("font_size")
	else:
		_money_value.add_theme_font_size_override("font_size", MONEY_SIZE_SIMPLE)


## Caption-over-value stat block.
func _make_block(caption_key: String, tip_key: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var caption := Label.new()
	caption.theme_type_variation = "TinyLabel"
	caption.text = L.t(caption_key)
	box.add_child(caption)
	var value := Label.new()
	value.theme_type_variation = "ValueLabel"
	value.text = "—"
	box.add_child(value)
	_attach_tip(box, caption_key, tip_key)
	return {"box": box, "value": value}


func _make_glyph_block(glyph: String, glyph_color: Color, caption_key: String, tip_key: String) -> Dictionary:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var g := Label.new()
	g.theme_type_variation = "GlyphLabel"
	g.add_theme_color_override("font_color", glyph_color)
	g.text = glyph
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(g)
	var block := _make_block(caption_key, tip_key)
	h.add_child(block["box"])
	return {"box": h, "value": block["value"]}


func _make_bottleneck_chip() -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = "ChipPanel"
	chip.focus_mode = Control.FOCUS_ALL
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiUtil.min_touch(chip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	chip.add_child(h)
	_bn_glyph = Label.new()
	_bn_glyph.theme_type_variation = "GlyphLabel"
	_bn_glyph.add_theme_color_override("font_color", UiTheme.COL_RED)
	_bn_glyph.text = "!"
	_bn_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_bn_glyph)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var caption := Label.new()
	caption.theme_type_variation = "TinyLabel"
	caption.text = L.t("ui.bottleneck")
	box.add_child(caption)
	_bn_value = Label.new()
	_bn_value.theme_type_variation = "ValueLabel"
	_bn_value.add_theme_color_override("font_color", UiTheme.COL_RED)
	_bn_value.text = "—"
	box.add_child(_bn_value)
	h.add_child(box)
	chip.gui_input.connect(_on_chip_input)
	_attach_tip(chip, "ui.bottleneck", "ui.tip_bottleneck")
	return chip


func _attach_tip(c: Control, caption_key: String, tip_key: String) -> void:
	if _tooltip != null:
		_tooltip.attach(c, _tip_rows.bind(caption_key, tip_key))


func _tip_rows(caption_key: String, tip_key: String) -> Array:
	return [
		TooltipScript.title_row(L.t(caption_key)),
		TooltipScript.dim_row(L.t(tip_key)),
	]


func _on_chip_input(event: InputEvent) -> void:
	var activate := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		activate = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event.is_action_pressed("ui_accept"):
		activate = true
	if activate and _bn_index >= 0:
		EventBus.station_selected.emit(_bn_index)
		accept_event()


func _refresh_once() -> void:
	var stats := UiUtil.stats_snapshot()
	if not stats.is_empty():
		_on_sim_stats(stats)


func _on_game_reset() -> void:
	_last_money = null
	_countup_hold = 0.0
	_refresh_once()


func _on_settings_changed(key: String, value: Variant) -> void:
	if key == "number_format":
		_last_money = null
		_refresh_once()
	elif key == "ui_mode":
		# Use the announced value (the field may still be session-local in stub era).
		_apply_money_size(UiUtil.resolve_ui_mode(value))


func _on_sim_stats(stats: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_tick_ms) / 1000.0, 0.0, 1.0)
	_last_tick_ms = now
	_countup_hold = maxf(_countup_hold - dt, 0.0)

	_update_money(stats.get("money"))
	UiUtil.set_label(_pps_value, UiUtil.per_sec(stats.get("pps", 0.0)))
	UiUtil.set_label(_oee_value, UiUtil.pct(float(stats.get("oee", 0.0))))
	UiUtil.set_label(_kp_value, UiUtil.fmt(stats.get("kp", 0.0)))
	_update_bottleneck(stats)


func _update_money(m: Variant) -> void:
	if typeof(m) != TYPE_OBJECT or m == null:
		return
	var big_jump := false
	if _last_money != null and m.has_method("sub") and _last_money.has_method("mul_f"):
		var diff: Variant = m.sub(_last_money)
		var thresh: Variant = _last_money.mul_f(0.25)
		if not bool(thresh.is_zero()):
			big_jump = bool(diff.gt(thresh))
	if big_jump and Juice.has_method("count_up") and not UiUtil.reduce_motion():
		Juice.count_up(_money_value, _last_money, m, _fmt_money)
		_countup_hold = 0.8
	elif _countup_hold <= 0.0:
		UiUtil.set_label(_money_value, _fmt_money(m))
	_last_money = m


func _fmt_money(v: Variant) -> String:
	return UiUtil.money(v)


func _update_bottleneck(stats: Dictionary) -> void:
	var bn := int(stats.get("bottleneck", -1))
	var bn_name := "—"
	if bn >= 0:
		var stations: Variant = stats.get("stations", [])
		if typeof(stations) == TYPE_ARRAY and bn < (stations as Array).size():
			var view: Variant = (stations as Array)[bn]
			if typeof(view) == TYPE_DICTIONARY:
				bn_name = str((view as Dictionary).get("name", str(bn)))
	_bn_index = bn
	UiUtil.set_label(_bn_value, bn_name)
	_bn_glyph.visible = bn >= 0
	_bn_chip.modulate = Color(1, 1, 1, 1.0 if bn >= 0 else 0.55)
