## SettingsPanel — audio sliders, reduce motion, screen shake, number format, camera
## sensitivity, save export/import (SaveManager string round-trip via a modal dialog),
## and the orbit/Gemba-walk controls hint. All reads/writes go through SettingsService
## with method-existence guards (degrades to direct property writes on the stub).
extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")

const MODE_EXPORT := 0
const MODE_IMPORT := 1

var _overlay: Control = null		# full-screen layer owned by hud.gd for modals
var _syncing := false

var _sliders: Dictionary = {}		# key -> HSlider
var _slider_values: Dictionary = {}	# key -> Label
var _reduce_check: CheckButton
var _format_option: OptionButton

var _modal: Control = null
var _modal_title: Label
var _modal_text: TextEdit
var _modal_mode := MODE_EXPORT
var _copy_btn: Button
var _paste_btn: Button
var _apply_btn: Button


func setup(overlay: Control) -> void:
	_overlay = overlay


func _ready() -> void:
	name = "SettingsPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	_section(v, "ui.settings_audio")
	_add_slider(v, "ui.settings_master", "master_volume", 0.0, 1.0, 0.01, 0.8)
	_add_slider(v, "ui.settings_music", "music_volume", 0.0, 1.0, 0.01, 0.7)
	_add_slider(v, "ui.settings_sfx", "sfx_volume", 0.0, 1.0, 0.01, 0.8)

	_section(v, "ui.settings_display")
	_reduce_check = CheckButton.new()
	_reduce_check.text = L.t("ui.settings_reduce_motion")
	UiUtil.min_touch(_reduce_check)
	_reduce_check.toggled.connect(_on_reduce_toggled)
	v.add_child(_reduce_check)
	_add_slider(v, "ui.settings_screen_shake", "screen_shake", 0.0, 1.0, 0.05, 0.3)

	var fmt_row := HBoxContainer.new()
	v.add_child(fmt_row)
	var fmt_caption := Label.new()
	fmt_caption.theme_type_variation = "DimLabel"
	fmt_caption.text = L.t("ui.settings_number_format")
	fmt_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fmt_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fmt_row.add_child(fmt_caption)
	_format_option = OptionButton.new()
	_format_option.add_item(L.t("ui.number_format_suffix"), 0)
	_format_option.add_item(L.t("ui.number_format_scientific"), 1)
	UiUtil.min_touch(_format_option, 150.0)
	_format_option.item_selected.connect(_on_format_selected)
	fmt_row.add_child(_format_option)

	_section(v, "ui.settings_controls")
	_add_slider(v, "ui.settings_camera_sensitivity", "camera_sensitivity", 0.2, 3.0, 0.05, 1.0)
	var hint := Label.new()
	hint.theme_type_variation = "DimLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.text = L.t("ui.walk_hint") + "\n" + L.t("ui.orbit_hint")
	v.add_child(hint)

	_section(v, "ui.settings_save")
	var save_row := HBoxContainer.new()
	v.add_child(save_row)
	var export_btn := Button.new()
	export_btn.text = L.t("ui.settings_export_save")
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiUtil.min_touch(export_btn)
	export_btn.pressed.connect(_open_modal.bind(MODE_EXPORT))
	save_row.add_child(export_btn)
	var import_btn := Button.new()
	import_btn.text = L.t("ui.settings_import_save")
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiUtil.min_touch(import_btn)
	import_btn.pressed.connect(_open_modal.bind(MODE_IMPORT))
	save_row.add_child(import_btn)

	EventBus.settings_changed.connect(_on_settings_changed)
	_sync_from_service()


func _section(parent: Control, key: String) -> void:
	if parent.get_child_count() > 0:
		var sep := HSeparator.new()
		parent.add_child(sep)
	var l := Label.new()
	l.theme_type_variation = "TitleLabel"
	l.text = L.t(key)
	parent.add_child(l)


func _add_slider(parent: Control, label_key: String, setting_key: String, minv: float, maxv: float, step: float, def: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := Label.new()
	caption.theme_type_variation = "DimLabel"
	caption.text = L.t(label_key)
	caption.custom_minimum_size = Vector2(130, 0)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = def
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiUtil.min_touch(slider)
	slider.value_changed.connect(_on_slider_changed.bind(setting_key))
	row.add_child(slider)
	var value := Label.new()
	value.theme_type_variation = "DimLabel"
	value.custom_minimum_size = Vector2(44, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	_sliders[setting_key] = slider
	_slider_values[setting_key] = value
	_update_slider_value_label(setting_key)


func _update_slider_value_label(key: String) -> void:
	var slider: HSlider = _sliders.get(key)
	var label: Label = _slider_values.get(key)
	if slider == null or label == null:
		return
	if slider.max_value <= 1.01:
		UiUtil.set_label(label, str(int(roundf(slider.value * 100.0))) + "%")
	else:
		UiUtil.set_label(label, UiUtil.trim_float(slider.value))


# ---------------------------------------------------------------- service round-trip

func _sync_from_service() -> void:
	_syncing = true
	for key in _sliders.keys():
		var slider: HSlider = _sliders[key]
		slider.set_value_no_signal(float(UiUtil.setting(str(key), slider.value)))
		_update_slider_value_label(str(key))
	_reduce_check.set_pressed_no_signal(bool(UiUtil.setting("reduce_motion", false)))
	_format_option.select(1 if str(UiUtil.setting("number_format", "suffix")) == "scientific" else 0)
	_syncing = false


func _write_setting(key: String, value: Variant) -> void:
	if _syncing:
		return
	if SettingsService.has_method("set_setting"):
		SettingsService.set_setting(key, value)
	elif SettingsService.has_method("set_value"):
		SettingsService.set_value(key, value)
	elif key in SettingsService:
		# Stub-era degradation: write the property and announce it ourselves.
		SettingsService.set(key, value)
		if SettingsService.has_method("save"):
			SettingsService.save()
		EventBus.settings_changed.emit(key, value)


func _on_slider_changed(value: float, key: String) -> void:
	_update_slider_value_label(key)
	_write_setting(key, value)


func _on_reduce_toggled(pressed: bool) -> void:
	_write_setting("reduce_motion", pressed)


func _on_format_selected(index: int) -> void:
	_write_setting("number_format", "scientific" if index == 1 else "suffix")


func _on_settings_changed(_key: String, _value: Variant) -> void:
	if not _syncing:
		_sync_from_service()


# ---------------------------------------------------------------- export/import modal

func _open_modal(mode: int) -> void:
	_modal_mode = mode
	if _modal == null:
		_build_modal()
	if _modal == null:
		return
	_modal.visible = true
	_modal_title.text = L.t("ui.settings_export_save" if mode == MODE_EXPORT else "ui.settings_import_save")
	_copy_btn.visible = mode == MODE_EXPORT
	_paste_btn.visible = mode == MODE_IMPORT
	_apply_btn.visible = mode == MODE_IMPORT
	_modal_text.editable = mode == MODE_IMPORT
	if mode == MODE_EXPORT:
		var exported := ""
		if SaveManager.has_method("export_string"):
			exported = str(SaveManager.export_string())
		_modal_text.text = exported
		_copy_btn.grab_focus()
	else:
		_modal_text.text = ""
		_modal_text.placeholder_text = L.t("ui.settings_paste_here")
		_modal_text.grab_focus()


func _build_modal() -> void:
	var parent: Control = _overlay if _overlay != null else self
	_modal = Control.new()
	_modal.name = "SaveModal"
	UiUtil.full_rect(_modal)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	parent.add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	UiUtil.full_rect(dim)
	_modal.add_child(dim)
	var center := CenterContainer.new()
	UiUtil.full_rect(center)
	_modal.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ModalPanel"
	panel.custom_minimum_size = Vector2(560, 360)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_modal_title = Label.new()
	_modal_title.theme_type_variation = "TitleLabel"
	v.add_child(_modal_title)
	_modal_text = TextEdit.new()
	_modal_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(_modal_text)
	var row := HBoxContainer.new()
	v.add_child(row)
	_copy_btn = Button.new()
	_copy_btn.text = L.t("ui.settings_copy")
	_copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiUtil.min_touch(_copy_btn)
	_copy_btn.pressed.connect(_on_copy_pressed)
	row.add_child(_copy_btn)
	_paste_btn = Button.new()
	_paste_btn.text = L.t("ui.settings_paste")
	_paste_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiUtil.min_touch(_paste_btn)
	_paste_btn.pressed.connect(_on_paste_pressed)
	row.add_child(_paste_btn)
	_apply_btn = Button.new()
	_apply_btn.theme_type_variation = "AccentButton"
	_apply_btn.text = L.t("ui.settings_apply")
	_apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiUtil.min_touch(_apply_btn)
	_apply_btn.pressed.connect(_on_apply_pressed)
	row.add_child(_apply_btn)
	var close_btn := Button.new()
	close_btn.text = L.t("ui.close")
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiUtil.min_touch(close_btn)
	close_btn.pressed.connect(_close_modal)
	row.add_child(close_btn)


func _input(event: InputEvent) -> void:
	if _modal != null and _modal.visible and event.is_action_pressed("ui_cancel"):
		_close_modal()
		get_viewport().set_input_as_handled()


func _close_modal() -> void:
	if _modal != null:
		_modal.visible = false


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_modal_text.text)
	EventBus.request_toast.emit(L.t("ui.toast_copied"))


func _on_paste_pressed() -> void:
	var clip := DisplayServer.clipboard_get()
	if clip != "":
		_modal_text.text = clip


func _on_apply_pressed() -> void:
	if not SaveManager.has_method("import_string"):
		EventBus.request_toast.emit(L.t("ui.toast_import_fail"))
		return
	var res: Variant = SaveManager.import_string(_modal_text.text.strip_edges())
	var ok := true
	if typeof(res) == TYPE_BOOL:
		ok = bool(res)
	EventBus.request_toast.emit(L.t("ui.toast_import_ok" if ok else "ui.toast_import_fail"))
	if ok:
		_close_modal()
