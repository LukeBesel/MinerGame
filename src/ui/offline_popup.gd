## OfflinePopup — "While you were away" modal shown on EventBus.offline_report:
## away duration, money earned counting up over 1.5 s (instant under reduce-motion),
## parts made, a capped notice when the offline cap kicked in, and a single OK button.
extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")

const COUNT_S := 1.5

var _panel_title: Label
var _away_label: Label
var _money_label: Label
var _parts_label: Label
var _capped_label: Label
var _ok_btn: Button
var _money = null			# BigNum from the report
var _tween: Tween = null


func _ready() -> void:
	name = "OfflinePopup"
	UiUtil.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	UiUtil.full_rect(dim)
	add_child(dim)

	var center := CenterContainer.new()
	UiUtil.full_rect(center)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ModalPanel"
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	_panel_title = Label.new()
	_panel_title.theme_type_variation = "TitleLabel"
	_panel_title.add_theme_font_size_override("font_size", 19)
	_panel_title.text = L.t("ui.offline_title")
	_panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_panel_title)

	_away_label = Label.new()
	_away_label.theme_type_variation = "DimLabel"
	_away_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_away_label)

	_money_label = Label.new()
	_money_label.theme_type_variation = "BigValueLabel"
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_money_label)

	_parts_label = Label.new()
	_parts_label.theme_type_variation = "DimLabel"
	_parts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_parts_label)

	_capped_label = Label.new()
	_capped_label.theme_type_variation = "AccentLabel"
	_capped_label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	_capped_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capped_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_capped_label.text = L.t("ui.offline_capped")
	v.add_child(_capped_label)

	_ok_btn = Button.new()
	_ok_btn.theme_type_variation = "AccentButton"
	_ok_btn.text = UiUtil.trf_or("ui.ok", [], L.t("ui.confirm"))
	_ok_btn.custom_minimum_size = Vector2(0, 44)
	_ok_btn.pressed.connect(_close)
	v.add_child(_ok_btn)

	EventBus.offline_report.connect(_on_offline_report)


func _on_offline_report(report: Dictionary) -> void:
	_money = report.get("money")
	var seconds := float(report.get("seconds", 0.0))
	# ui.offline_body: "The night shift kept the line running: {0} earned in {1}."
	UiUtil.set_label(_away_label, UiUtil.trf("ui.offline_body", [UiUtil.money(_money if _money != null else 0.0), UiUtil.duration(seconds)]))
	UiUtil.set_label(_parts_label, UiUtil.trf("ui.offline_parts", [UiUtil.fmt(report.get("parts", 0.0))]))
	_capped_label.visible = bool(report.get("capped", false))
	visible = true
	_ok_btn.grab_focus()
	_start_count()


func _start_count() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var can_count: bool = _money != null and typeof(_money) == TYPE_OBJECT and _money.has_method("mul_f")
	if UiUtil.reduce_motion() or not can_count:
		_set_money_progress(1.0)
		return
	_set_money_progress(0.0)
	_tween = create_tween()
	_tween.tween_method(_set_money_progress, 0.0, 1.0, COUNT_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_money_progress(p: float) -> void:
	if _money == null:
		UiUtil.set_label(_money_label, UiUtil.money(0.0))
		return
	var shown: Variant = _money
	if p < 1.0 and typeof(_money) == TYPE_OBJECT and _money.has_method("mul_f"):
		shown = _money.mul_f(clampf(p, 0.0, 1.0))
	UiUtil.set_label(_money_label, "+" + UiUtil.money(shown))


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept")):
		# Either confirm key dismisses; skip while the OK button itself has focus
		# (ui_accept there activates the button normally).
		if event.is_action_pressed("ui_accept") and _ok_btn.has_focus():
			return
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_set_money_progress(1.0)
	visible = false
