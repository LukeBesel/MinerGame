## KaizenPanel — the prestige ("Kaizen Event") tab: explanation, lifetime-parts progress,
## CIP gain preview (multiplier now → after), a big amber button gated behind can_prestige
## plus an are-you-sure confirm step, and a brief congrats state after prestige_performed.
extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const TooltipScript = preload("res://src/ui/tooltip.gd")

const REFRESH_S := 0.5
const CONGRATS_S := 6.0

var _tooltip = null
var _lifetime_value: Label
var _progress: ProgressBar
var _progress_text: Label
var _gain_value: Label
var _mult_value: Label
var _cta: Button
var _requirement: Label
var _confirm_box: PanelContainer
var _congrats_box: PanelContainer
var _congrats_body: Label
var _main_box: VBoxContainer

var _refresh_left := 0.0
var _congrats_token := 0


func setup(tooltip) -> void:
	_tooltip = tooltip


func _ready() -> void:
	name = "KaizenPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	_main_box = v

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.add_theme_font_size_override("font_size", 18)
	title.text = L.t("ui.prestige_title")
	v.add_child(title)

	var explain := Label.new()
	explain.theme_type_variation = "DimLabel"
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explain.text = L.t("ui.prestige_explain")
	v.add_child(explain)

	# Progress toward the minimum lifetime parts.
	var inset := PanelContainer.new()
	inset.theme_type_variation = "InsetPanel"
	v.add_child(inset)
	var inset_v := VBoxContainer.new()
	inset_v.add_theme_constant_override("separation", 4)
	inset.add_child(inset_v)
	var lifetime_row := HBoxContainer.new()
	inset_v.add_child(lifetime_row)
	var lifetime_caption := Label.new()
	lifetime_caption.theme_type_variation = "DimLabel"
	lifetime_caption.text = L.t("ui.stats_lifetime_parts")
	lifetime_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lifetime_row.add_child(lifetime_caption)
	_lifetime_value = Label.new()
	_lifetime_value.theme_type_variation = "ValueLabel"
	lifetime_row.add_child(_lifetime_value)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.custom_minimum_size = Vector2(0, 12)
	inset_v.add_child(_progress)
	_progress_text = Label.new()
	_progress_text.theme_type_variation = "TinyLabel"
	inset_v.add_child(_progress_text)

	# Preview: CIP gain + multiplier change (full-sentence locale templates).
	var preview := VBoxContainer.new()
	preview.add_theme_constant_override("separation", 4)
	v.add_child(preview)
	_gain_value = Label.new()
	_gain_value.theme_type_variation = "AccentLabel"
	_gain_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gain_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_child(_gain_value)
	_mult_value = Label.new()
	_mult_value.theme_type_variation = "ValueLabel"
	_mult_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mult_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_child(_mult_value)
	if _tooltip != null:
		_tooltip.attach(preview, _tip_cip)

	_cta = Button.new()
	_cta.theme_type_variation = "AccentButton"
	_cta.custom_minimum_size = Vector2(0, 52)
	_cta.text = L.t("ui.prestige_button")
	_cta.disabled = true
	_cta.pressed.connect(_on_cta_pressed)
	v.add_child(_cta)

	_requirement = Label.new()
	_requirement.theme_type_variation = "DimLabel"
	_requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_requirement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_requirement)

	# Confirm step.
	_confirm_box = PanelContainer.new()
	_confirm_box.theme_type_variation = "InsetPanel"
	_confirm_box.visible = false
	v.add_child(_confirm_box)
	var confirm_v := VBoxContainer.new()
	confirm_v.add_theme_constant_override("separation", 8)
	_confirm_box.add_child(confirm_v)
	var confirm_body := Label.new()
	confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_body.text = L.t("ui.prestige_confirm")
	confirm_v.add_child(confirm_body)
	var confirm_row := HBoxContainer.new()
	confirm_v.add_child(confirm_row)
	var cancel := Button.new()
	cancel.text = L.t("ui.cancel")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiUtil.min_touch(cancel)
	cancel.pressed.connect(_on_cancel_pressed)
	confirm_row.add_child(cancel)
	var confirm := Button.new()
	confirm.theme_type_variation = "AccentButton"
	confirm.text = L.t("ui.confirm")
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiUtil.min_touch(confirm)
	confirm.pressed.connect(_on_confirm_pressed)
	confirm_row.add_child(confirm)

	# Congrats state.
	_congrats_box = PanelContainer.new()
	_congrats_box.theme_type_variation = "CoachPanel"
	_congrats_box.visible = false
	v.add_child(_congrats_box)
	var congrats_v := VBoxContainer.new()
	_congrats_box.add_child(congrats_v)
	var congrats_title := Label.new()
	congrats_title.theme_type_variation = "AccentLabel"
	congrats_title.text = L.t("ui.prestige_done_title")
	congrats_v.add_child(congrats_title)
	_congrats_body = Label.new()
	_congrats_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_congrats_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	congrats_v.add_child(_congrats_body)

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.prestige_performed.connect(_on_prestige_performed)
	EventBus.game_reset.connect(_on_game_reset)
	_refresh_view()


func _on_sim_stats(_stats: Dictionary) -> void:
	_refresh_left -= 0.1
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_S
		_refresh_view()


func _refresh_view() -> void:
	var pv := UiUtil.prestige_view()
	var can := bool(pv.get("can_prestige", false))
	var lifetime: Variant = pv.get("lifetime_parts")
	var min_parts: Variant = pv.get("min_parts")
	UiUtil.set_label(_lifetime_value, UiUtil.fmt(lifetime) if lifetime != null else "—")
	var ratio := 0.0
	if can:
		ratio = 1.0
	elif lifetime != null and min_parts != null and typeof(lifetime) == TYPE_OBJECT and lifetime.has_method("div"):
		var r: Variant = lifetime.div(min_parts)
		if typeof(r) == TYPE_OBJECT and r.has_method("to_float"):
			ratio = clampf(float(r.to_float()), 0.0, 1.0)
	_progress.value = ratio
	var min_text := UiUtil.fmt(min_parts) if min_parts != null else "—"
	UiUtil.set_label(_progress_text, UiUtil.fmt(lifetime) + " / " + min_text if lifetime != null else "—")
	UiUtil.set_label(_gain_value, UiUtil.trf("ui.prestige_gain", [UiUtil.fmt(pv.get("cip_gain", 0))]) if not pv.is_empty() else "—")
	var mult_now := float(pv.get("multiplier_now", 1.0))
	var mult_after := float(pv.get("multiplier_after", 1.0))
	UiUtil.set_label(_mult_value, UiUtil.trf("ui.prestige_mult", [UiUtil.trim_float(mult_now), UiUtil.trim_float(mult_after)]))
	_cta.disabled = not can
	_requirement.visible = not can
	if not can:
		UiUtil.set_label(_requirement, UiUtil.trf("ui.prestige_locked", [min_text]))
	if can and _congrats_box.visible:
		pass	# leave congrats visible until its timer clears it


func _on_cta_pressed() -> void:
	if not UiUtil.game_ready():
		return
	_confirm_box.visible = true
	_cta.visible = false
	_congrats_box.visible = false


func _on_cancel_pressed() -> void:
	_confirm_box.visible = false
	_cta.visible = true


func _on_confirm_pressed() -> void:
	if not UiUtil.game_ready():
		return
	_confirm_box.visible = false
	_cta.visible = true
	if not UiUtil.game_cmd("do_prestige") and AudioDirector.has_method("play"):
		AudioDirector.play("error")


func _on_prestige_performed(cip_gained: int, new_multiplier: float) -> void:
	_confirm_box.visible = false
	_cta.visible = true
	_congrats_box.visible = true
	UiUtil.set_label(_congrats_body, UiUtil.trf("ui.prestige_done_body", [str(cip_gained), UiUtil.mult_x(new_multiplier)]))
	_congrats_token += 1
	var token := _congrats_token
	var t := get_tree().create_timer(CONGRATS_S)
	t.timeout.connect(func() -> void:
		if token == _congrats_token and is_instance_valid(_congrats_box):
			_congrats_box.visible = false)
	_refresh_view()


func _on_game_reset() -> void:
	_confirm_box.visible = false
	_cta.visible = true
	_refresh_view()


func _tip_cip() -> Array:
	return [
		TooltipScript.title_row(L.t("ui.prestige_title")),
		TooltipScript.dim_row(L.t("ui.tip_cip")),
	]
