## MobileOverlay — full-screen host for one borrowed right-panel tab in the MOBILE
## layout: header with the tab title and a big ✕ close button, content slot underneath.
## The tab panel is reparented in by hud.gd (right_panel.borrow_panel) and handed back on
## close, so all tab logic stays in the existing panels. ui_cancel closes.
extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")

signal closed

var _title: Label
var _slot: VBoxContainer
var _content: Control = null


func _ready() -> void:
	name = "MobileOverlay"
	UiUtil.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = UiTheme.COL_BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiUtil.full_rect(backdrop)
	add_child(backdrop)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	UiUtil.anchor_box(v, 0.0, 0.0, 1.0, 1.0, 8.0, 8.0, -8.0, -8.0)
	add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	v.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.add_theme_font_size_override("font_size", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_title)
	var close_btn := Button.new()
	close_btn.theme_type_variation = "CloseButton"
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.custom_minimum_size = Vector2(UiTheme.TOUCH_MIN_MOBILE + 8.0, UiTheme.TOUCH_MIN_MOBILE + 8.0)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	_slot = VBoxContainer.new()
	_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_slot)


## Show the overlay hosting `panel` (already borrowed from right_panel by hud.gd).
func open(panel: Control, title: String) -> void:
	if panel == null:
		return
	if _content != null and _content != panel:
		_release_content()
	_content = panel
	if panel.get_parent() != null and panel.get_parent() != _slot:
		panel.get_parent().remove_child(panel)
	if panel.get_parent() == null:
		_slot.add_child(panel)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.visible = true
	UiUtil.set_label(_title, title)
	visible = true


## Hide and hand the content back (hud returns it to right_panel on `closed`).
func close() -> void:
	if not visible:
		return
	visible = false
	_release_content()
	closed.emit()


func _release_content() -> void:
	if _content != null and is_instance_valid(_content) and _content.get_parent() == _slot:
		_slot.remove_child(_content)
	_content = null


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
