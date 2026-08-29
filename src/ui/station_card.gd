## StationCard — one production-line card: status icon + name, tiny stat row
## (throughput / quality / WIP), and the 4 upgrade buttons (or one big Unlock button).
## Upgrades that help the CURRENT bottleneck and are affordable get the amber glow
## (pillar #1: the helping purchase is always highlighted).
extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const TooltipScript = preload("res://src/ui/tooltip.gd")

var index := -1

var _tooltip = null
var _name_label: Label
var _glyph: Label
var _status_word: Label
var _locked_box: VBoxContainer
var _unlock_btn: Button
var _open_box: VBoxContainer
var _thr_value: Label
var _q_value: Label
var _wip_bar: ProgressBar
var _wip_dash: Label
var _upgrade_btns: Dictionary = {}		# uid -> Button
var _hot: Dictionary = {}				# uid -> bool
var _pulse_tweens: Dictionary = {}		# uid -> Tween

var _view: Dictionary = {}
var _selected := false


func setup(station_index: int, tooltip) -> void:
	index = station_index
	_tooltip = tooltip
	name = "StationCard%d" % index
	theme_type_variation = "CardPanel"
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_card_input)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	# Header: status glyph + name + status word.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	v.add_child(header)
	_glyph = Label.new()
	_glyph.theme_type_variation = "GlyphLabel"
	_glyph.text = "○"
	header.add_child(_glyph)
	_name_label = Label.new()
	_name_label.theme_type_variation = "TitleLabel"
	_name_label.text = "—"
	_name_label.clip_text = true
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name_label)
	_status_word = Label.new()
	_status_word.theme_type_variation = "TinyLabel"
	header.add_child(_status_word)
	if _tooltip != null:
		_tooltip.attach(self, _tip_station)

	# Locked state: one big unlock button.
	_locked_box = VBoxContainer.new()
	_locked_box.visible = false
	v.add_child(_locked_box)
	var locked_note := Label.new()
	locked_note.theme_type_variation = "DimLabel"
	locked_note.text = L.t("ui.locked")
	_locked_box.add_child(locked_note)
	_unlock_btn = Button.new()
	_unlock_btn.theme_type_variation = "AccentButton"
	UiUtil.min_touch(_unlock_btn, 0.0)
	_unlock_btn.custom_minimum_size.y = 44.0
	_unlock_btn.pressed.connect(_on_unlock_pressed)
	_locked_box.add_child(_unlock_btn)
	if _tooltip != null:
		_tooltip.attach(_unlock_btn, _tip_unlock)

	# Unlocked state: stat row + upgrade grid.
	_open_box = VBoxContainer.new()
	_open_box.add_theme_constant_override("separation", 6)
	_open_box.visible = false
	v.add_child(_open_box)

	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 14)
	_open_box.add_child(stat_row)
	var thr_block := _stat_block("ui.throughput")
	_thr_value = thr_block["value"]
	stat_row.add_child(thr_block["box"])
	var q_block := _stat_block("ui.quality")
	_q_value = q_block["value"]
	stat_row.add_child(q_block["box"])
	var wip_box := VBoxContainer.new()
	wip_box.add_theme_constant_override("separation", 2)
	wip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wip_caption := Label.new()
	wip_caption.theme_type_variation = "TinyLabel"
	wip_caption.text = L.t("ui.wip")
	wip_box.add_child(wip_caption)
	_wip_bar = ProgressBar.new()
	_wip_bar.show_percentage = false
	_wip_bar.custom_minimum_size = Vector2(64, 10)
	_wip_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wip_bar.max_value = 1.0
	_wip_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	wip_box.add_child(_wip_bar)
	_wip_dash = Label.new()
	_wip_dash.theme_type_variation = "TinyLabel"
	_wip_dash.text = "—"
	_wip_dash.visible = false
	wip_box.add_child(_wip_dash)
	stat_row.add_child(wip_box)
	if _tooltip != null:
		_tooltip.attach(thr_block["box"], _tip_stat.bind("ui.throughput", "ui.tip_throughput"))
		_tooltip.attach(q_block["box"], _tip_stat.bind("ui.quality", "ui.tip_quality"))
		_tooltip.attach(wip_box, _tip_wip)

	var grid := GridContainer.new()
	grid.columns = 2
	_open_box.add_child(grid)
	for uid in UiUtil.UPGRADE_IDS:
		var b := Button.new()
		b.theme_type_variation = "UpgradeButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		b.text = UiUtil.upgrade_display_name(index, str(uid))
		b.pressed.connect(_on_upgrade_pressed.bind(str(uid)))
		grid.add_child(b)
		_upgrade_btns[uid] = b
		_hot[uid] = false
		if _tooltip != null:
			_tooltip.attach(b, _tip_upgrade.bind(str(uid)))


func _stat_block(caption_key: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var caption := Label.new()
	caption.theme_type_variation = "TinyLabel"
	caption.text = L.t(caption_key)
	box.add_child(caption)
	var value := Label.new()
	value.theme_type_variation = "ValueLabel"
	value.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	value.text = "—"
	box.add_child(value)
	return {"box": box, "value": value}


# ---------------------------------------------------------------- updates (10 Hz)

## view: station view dict; upviews: uid -> upgrade view dict; money: BigNum (may be null).
func update_view(view: Dictionary, upviews: Dictionary, money: Variant) -> void:
	_view = view
	var unlocked := bool(view.get("unlocked", false))
	var is_bn := bool(view.get("is_bottleneck", false))
	var status := int(view.get("status", -1))

	UiUtil.set_label(_name_label, str(view.get("name", str(index))))
	_name_label.add_theme_color_override("font_color", UiTheme.COL_RED if is_bn else UiTheme.COL_TEXT)
	UiUtil.set_label(_glyph, UiUtil.status_glyph(status, is_bn) if unlocked else "○")
	_glyph.add_theme_color_override("font_color", UiUtil.status_color(status, is_bn) if unlocked else UiTheme.COL_TEXT_DISABLED)
	UiUtil.set_label(_status_word, UiUtil.status_name(status, is_bn) if unlocked else "")

	_locked_box.visible = not unlocked
	_open_box.visible = unlocked
	if not unlocked:
		_update_locked(view, money)
		return

	UiUtil.set_label(_thr_value, UiUtil.per_sec(view.get("throughput", 0.0)))
	var stats_v: Variant = view.get("stats", {})
	var q := 0.0
	if typeof(stats_v) == TYPE_DICTIONARY:
		q = float((stats_v as Dictionary).get("quality", 0.0))
	UiUtil.set_label(_q_value, UiUtil.pct(q))
	var cap := float(view.get("buffer_in_cap", 0.0))
	if cap > 0.0:
		_wip_bar.visible = true
		_wip_dash.visible = false
		_wip_bar.value = clampf(float(view.get("buffer_in", 0.0)) / cap, 0.0, 1.0)
	else:
		_wip_bar.visible = false
		_wip_dash.visible = true

	for uid in UiUtil.UPGRADE_IDS:
		_update_upgrade_btn(str(uid), upviews.get(uid, {}), view)


func _update_locked(view: Dictionary, money: Variant) -> void:
	var cost: Variant = view.get("unlock_cost")
	var cost_text := UiUtil.money(cost) if cost != null else "—"
	UiUtil.set_btn(_unlock_btn, L.t("ui.unlock") + "  ·  " + cost_text)
	var affordable := false
	if money != null and typeof(money) == TYPE_OBJECT and cost != null and money.has_method("ge"):
		affordable = bool(money.ge(cost))
	_unlock_btn.disabled = not affordable


func _update_upgrade_btn(uid: String, uv_v: Variant, view: Dictionary) -> void:
	var b: Button = _upgrade_btns.get(uid)
	if b == null:
		return
	var uv: Dictionary = uv_v if typeof(uv_v) == TYPE_DICTIONARY else {}
	var levels_v: Variant = view.get("upgrade_levels", {})
	var lvl := 0
	if typeof(levels_v) == TYPE_DICTIONARY:
		lvl = int((levels_v as Dictionary).get(uid, 0))
	var upgrade_name := UiUtil.upgrade_display_name(index, uid)
	var line1 := upgrade_name + "  " + L.t("ui.level") + " " + str(lvl)
	var maxed := bool(uv.get("maxed", false))
	var line2 := ""
	if maxed:
		line2 = L.t("ui.max")
	elif uv.is_empty():
		line2 = "—"
	else:
		line2 = UiUtil.money(uv.get("cost"))
		var count := int(uv.get("count", 1))
		if count > 1:
			line2 += "  ×" + str(count)
	UiUtil.set_btn(b, line1 + "\n" + line2)
	var affordable := bool(uv.get("affordable", false))
	b.disabled = maxed or not affordable
	var hot: bool = bool(uv.get("helps_bottleneck", false)) and affordable and not maxed
	_apply_hot(uid, b, hot)


func _apply_hot(uid: String, b: Button, hot: bool) -> void:
	if bool(_hot.get(uid, false)) == hot:
		return
	_hot[uid] = hot
	b.theme_type_variation = "UpgradeButtonHot" if hot else "UpgradeButton"
	var old: Variant = _pulse_tweens.get(uid)
	if typeof(old) == TYPE_OBJECT and old != null and old.has_method("kill"):
		old.kill()
	_pulse_tweens.erase(uid)
	b.self_modulate = Color(1, 1, 1, 1)
	if hot and not UiUtil.reduce_motion():
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(b, "self_modulate", Color(1.16, 1.1, 0.9, 1.0), 0.65).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "self_modulate", Color(1, 1, 1, 1), 0.65).set_trans(Tween.TRANS_SINE)
		_pulse_tweens[uid] = tw


func set_selected(sel: bool) -> void:
	if _selected == sel:
		return
	_selected = sel
	theme_type_variation = "CardPanelSelected" if sel else "CardPanel"


# ---------------------------------------------------------------- input / commands

func _on_card_input(event: InputEvent) -> void:
	var activate := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		activate = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event.is_action_pressed("ui_accept"):
		activate = true
	if activate:
		grab_focus()
		EventBus.station_selected.emit(index)
		accept_event()


func _on_unlock_pressed() -> void:
	if not UiUtil.game_ready():
		return
	if not UiUtil.game_cmd("unlock_station", [index]) and AudioDirector.has_method("play"):
		AudioDirector.play("error")


func _on_upgrade_pressed(uid: String) -> void:
	if not UiUtil.game_ready():
		return
	if not UiUtil.game_cmd("buy_upgrade", [index, uid]) and AudioDirector.has_method("play"):
		AudioDirector.play("error")


# ---------------------------------------------------------------- tooltips

func _tip_station() -> Array:
	var rows: Array = []
	var unlocked := bool(_view.get("unlocked", false))
	rows.append(TooltipScript.title_row(str(_view.get("name", ""))))
	if not unlocked:
		rows.append(TooltipScript.dim_row(L.t("ui.locked")))
		rows.append(TooltipScript.accent_row(UiUtil.money(_view.get("unlock_cost"))))
		return rows
	var status := int(_view.get("status", -1))
	var is_bn := bool(_view.get("is_bottleneck", false))
	var srow := TooltipScript.row(UiUtil.status_name(status, is_bn), UiUtil.status_color(status, is_bn), UiTheme.FONT_SMALL)
	rows.append(srow)
	var stats_v: Variant = _view.get("stats", {})
	if typeof(stats_v) == TYPE_DICTIONARY:
		var s: Dictionary = stats_v
		rows.append(TooltipScript.dim_row(L.t("ui.cycle_time") + ": " + UiUtil.trim_float(float(s.get("cycle_time", 0.0))) + "s"))
		rows.append(TooltipScript.dim_row(L.t("ui.uptime") + ": " + UiUtil.pct(float(s.get("uptime", 0.0)))))
		rows.append(TooltipScript.dim_row(L.t("ui.quality") + ": " + UiUtil.pct(float(s.get("quality", 0.0)))))
		rows.append(TooltipScript.dim_row(L.t("ui.changeover") + ": " + UiUtil.trim_float(float(s.get("changeover_time", 0.0))) + "s"))
		rows.append(TooltipScript.dim_row(L.t("ui.capacity") + ": " + str(int(s.get("capacity", 0)))))
	rows.append(TooltipScript.dim_row(L.t("ui.throughput") + ": " + UiUtil.per_sec(_view.get("throughput", 0.0))))
	var scrap := float(_view.get("scrap_rate", 0.0))
	if scrap > 0.0005:
		rows.append(TooltipScript.row(L.t("ui.scrap") + ": " + UiUtil.per_sec(scrap), UiTheme.COL_RED, UiTheme.FONT_SMALL))
	if is_bn:
		rows.append(TooltipScript.accent_row(L.t("ui.tip_bottleneck")))
	return rows


func _tip_stat(caption_key: String, tip_key: String) -> Array:
	return [
		TooltipScript.title_row(L.t(caption_key)),
		TooltipScript.dim_row(L.t(tip_key)),
	]


func _tip_wip() -> Array:
	var cap := float(_view.get("buffer_in_cap", 0.0))
	var rows: Array = [TooltipScript.title_row(L.t("ui.wip"))]
	if cap > 0.0:
		rows.append(TooltipScript.row(str(int(float(_view.get("buffer_in", 0.0)))) + " / " + str(int(cap)), UiTheme.COL_TEXT, UiTheme.FONT_SMALL))
	rows.append(TooltipScript.dim_row(L.t("ui.tip_wip")))
	return rows


func _tip_unlock() -> Array:
	return [
		TooltipScript.title_row(L.t("ui.unlock") + " · " + str(_view.get("name", ""))),
		TooltipScript.dim_row(L.t("ui.tip_unlock")),
		TooltipScript.accent_row(UiUtil.money(_view.get("unlock_cost"))),
	]


func _tip_upgrade(uid: String) -> Array:
	var rows: Array = []
	rows.append(TooltipScript.title_row(UiUtil.upgrade_display_name(index, uid)))
	rows.append(TooltipScript.dim_row(L.t("ui.tip_upgrade_" + uid)))
	var def := UiUtil.upgrade_def(index, uid)
	var eff_v: Variant = def.get("effect", {})
	if typeof(eff_v) == TYPE_DICTIONARY and not (eff_v as Dictionary).is_empty():
		rows.append(TooltipScript.row(UiUtil.upgrade_effect_text(eff_v), UiTheme.COL_GREEN, UiTheme.FONT_SMALL))
	var uv := UiUtil.upgrade_view(index, uid)
	if bool(uv.get("maxed", false)):
		rows.append(TooltipScript.accent_row(L.t("ui.max")))
	elif not uv.is_empty():
		var count := int(uv.get("count", 1))
		var cost_line := L.t("ui.cost") + ": " + UiUtil.money(uv.get("cost"))
		if count > 1:
			cost_line += "  ×" + str(count)
		rows.append(TooltipScript.accent_row(cost_line))
	if bool(uv.get("helps_bottleneck", false)):
		rows.append(TooltipScript.row(L.t("ui.helps_bottleneck"), UiTheme.COL_AMBER, UiTheme.FONT_SMALL))
	return rows
