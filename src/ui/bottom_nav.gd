## BottomNav — the MOBILE bottom navigation bar: four ≥48px two-line buttons
## (Skills / Kaizen / Stats / Settings) that open the existing right-panel tabs as
## full-screen overlays (hud.gd wires tab_selected to the MobileOverlay).
extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")

signal tab_selected(index: int)

const GLYPHS := ["◆", "↻", "≡", "⚙"]
const TITLE_KEYS := ["ui.tab_skills", "ui.tab_kaizen", "ui.tab_stats", "ui.tab_settings"]
const BTN_MIN_H := 56.0

var _btns: Array = []


func _ready() -> void:
	name = "BottomNav"
	theme_type_variation = "NavPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	add_child(row)
	for i in TITLE_KEYS.size():
		var b := Button.new()
		b.theme_type_variation = "NavButton"
		b.toggle_mode = true
		b.text = str(GLYPHS[i]) + "\n" + L.t(str(TITLE_KEYS[i]))
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(UiTheme.TOUCH_MIN_MOBILE, BTN_MIN_H)
		b.pressed.connect(_on_pressed.bind(i))
		row.add_child(b)
		_btns.append(b)


func _on_pressed(i: int) -> void:
	if AudioDirector.has_method("play"):
		AudioDirector.play("tab")
	tab_selected.emit(i)


## Reflect which overlay is open (-1 = none) in the buttons' pressed state.
func set_active(i: int) -> void:
	for j in _btns.size():
		(_btns[j] as Button).set_pressed_no_signal(j == i)


## Global rect of the Skills button — the MOBILE "skills_tab" onboarding target.
func skills_rect() -> Rect2:
	if _btns.size() > 0:
		var b: Button = _btns[0]
		if is_instance_valid(b) and b.is_visible_in_tree():
			return b.get_global_rect()
	return Rect2()
