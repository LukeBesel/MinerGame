## Toasts — notification stack: request_toast, save completed/failed, achievement
## unlocked, and milestone reached (+KP, slightly celebratory). Auto-fade, never blocks
## clicks into the 3D world. DESKTOP stacks bottom-right; MOBILE stacks bottom-center
## above the bottom sheet (hud.gd drives set_layout_mode / set_bottom_clearance).
extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const Layout = preload("res://src/ui/layout.gd")

const MAX_TOASTS := 5
const LIFETIME_S := 3.5
const LIFETIME_BIG_S := 5.0
const TOAST_W := 300.0

var _box: VBoxContainer
var _layout_mode := Layout.MODE_DESKTOP
var _clearance := 8.0			# MOBILE: keep the stack above sheet + nav


func _ready() -> void:
	name = "Toasts"
	UiUtil.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.add_theme_constant_override("separation", 6)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_apply_box_anchor()
	add_child(_box)

	EventBus.request_toast.connect(_on_request_toast)
	EventBus.save_completed.connect(_on_save_completed)
	EventBus.save_failed.connect(_on_save_failed)
	EventBus.achievement_unlocked.connect(_on_achievement)
	EventBus.milestone_reached.connect(_on_milestone)


## hud.gd: DESKTOP = bottom-right stack, MOBILE = bottom-center above the sheet.
func set_layout_mode(mode: int) -> void:
	if _layout_mode == mode:
		return
	_layout_mode = mode
	_apply_box_anchor()


## MOBILE: distance from the screen bottom to the toast stack (sheet + nav + gap).
func set_bottom_clearance(px: float) -> void:
	if is_equal_approx(_clearance, px):
		return
	_clearance = px
	_apply_box_anchor()


func _apply_box_anchor() -> void:
	if _box == null:
		return
	if _layout_mode == Layout.MODE_MOBILE:
		var half := TOAST_W * 0.5
		UiUtil.anchor_box(_box, 0.5, 1.0, 0.5, 1.0, -half, -_clearance, half, -_clearance)
		_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	else:
		UiUtil.anchor_box(_box, 1.0, 1.0, 1.0, 1.0, -TOAST_W - 8.0, -8.0, -8.0, -8.0)
		_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _on_request_toast(text: String) -> void:
	_spawn(text, false)


func _on_save_completed(_slot: String) -> void:
	_spawn(L.t("ui.toast_save_ok"), false)


func _on_save_failed(reason: String) -> void:
	_spawn(UiUtil.trf("ui.toast_save_fail", [reason]), false)


func _on_achievement(id: String) -> void:
	_spawn(UiUtil.trf("ui.toast_achievement", [_lookup_name("achievements", id)]), true)


func _on_milestone(id: String, kp_gained: int) -> void:
	_spawn(UiUtil.trf("ui.toast_milestone", [_lookup_name("milestones", id), UiUtil.kp_amount(kp_gained)]), true)


## Localized display name for a milestone/achievement id from Data.db (falls back to id).
func _lookup_name(list_key: String, id: String) -> String:
	for entry in UiUtil.db_list(list_key):
		if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("id", "")) == id:
			return L.t(str((entry as Dictionary).get("name_key", id)))
	return id


func _spawn(text: String, celebratory: bool) -> void:
	if text.strip_edges() == "":
		return
	while _box.get_child_count() >= MAX_TOASTS:
		var oldest := _box.get_child(0)
		_box.remove_child(oldest)
		oldest.queue_free()

	var panel := PanelContainer.new()
	panel.theme_type_variation = "ToastPanelGood" if celebratory else "ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	if celebratory:
		var glyph := Label.new()
		glyph.theme_type_variation = "GlyphLabel"
		glyph.add_theme_color_override("font_color", UiTheme.COL_AMBER)
		glyph.text = "◆"
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(glyph)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TOAST_W - 60.0, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if celebratory:
		label.add_theme_color_override("font_color", Color("#FFE1A1"))
	row.add_child(label)
	_box.add_child(panel)

	var life := LIFETIME_BIG_S if celebratory else LIFETIME_S
	if UiUtil.reduce_motion():
		var tw := create_tween()
		tw.tween_interval(life)
		tw.tween_callback(panel.queue_free)
		return
	# Containers own child position, so animate opacity/scale only (layout-safe).
	panel.modulate = Color(1, 1, 1, 0)
	panel.pivot_offset = Vector2(TOAST_W, 20.0)
	panel.scale = Vector2(0.99, 0.9) if not celebratory else Vector2(0.9, 0.9)
	var tw2 := create_tween()
	tw2.tween_property(panel, "modulate:a", 1.0, 0.2)
	var trans := Tween.TRANS_BACK if celebratory else Tween.TRANS_CUBIC
	tw2.parallel().tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(trans).set_ease(Tween.EASE_OUT)
	tw2.tween_interval(life)
	tw2.tween_property(panel, "modulate:a", 0.0, 0.35)
	tw2.tween_callback(panel.queue_free)
