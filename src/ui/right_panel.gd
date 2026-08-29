## RightPanel — tabbed side panel: Skill Tree / Kaizen Event / Stats / Settings.
## Custom tab buttons (localized, keyboard-focusable); the Kaizen and Skills tabs get an
## amber alert tint when a prestige or an affordable skill is waiting (pillar #1).
extends PanelContainer

const UiUtil = preload("res://src/ui/ui_util.gd")
const SkillTreePanel = preload("res://src/ui/skill_tree_panel.gd")
const KaizenPanel = preload("res://src/ui/kaizen_panel.gd")
const StatsPanel = preload("res://src/ui/stats_panel.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")

const TAB_SKILLS := 0
const TAB_KAIZEN := 1
const TAB_STATS := 2
const TAB_SETTINGS := 3
const ALERT_POLL_S := 1.0

var _tab_btns: Array = []
var _panels: Array = []
var _active := TAB_SKILLS
var _alert_left := 0.0
var _skills_alert := false
var _kaizen_alert := false


func setup(tooltip, overlay: Control) -> void:
	var skills = SkillTreePanel.new()
	skills.setup(tooltip)
	var kaizen = KaizenPanel.new()
	kaizen.setup(tooltip)
	var stats = StatsPanel.new()
	var settings = SettingsPanel.new()
	settings.setup(overlay)
	_panels = [skills, kaizen, stats, settings]


func _ready() -> void:
	name = "RightPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	v.add_child(tab_row)
	var titles := ["ui.tab_skills", "ui.tab_kaizen", "ui.tab_stats", "ui.tab_settings"]
	for i in titles.size():
		var b := Button.new()
		b.theme_type_variation = "TabButton"
		b.toggle_mode = true
		b.text = L.t(str(titles[i]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		UiUtil.min_touch(b)
		b.pressed.connect(_on_tab_pressed.bind(i))
		tab_row.add_child(b)
		_tab_btns.append(b)

	var content := PanelContainer.new()
	content.theme_type_variation = "InsetPanel"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	for p in _panels:
		content.add_child(p)

	EventBus.sim_stats.connect(_on_sim_stats)
	_apply_active()


func _on_tab_pressed(i: int) -> void:
	if i == _active:
		_apply_active()	# keep the toggle pressed even when re-clicked
		return
	_active = i
	_apply_active()
	if AudioDirector.has_method("play"):
		AudioDirector.play("tab")


func _apply_active() -> void:
	for i in _tab_btns.size():
		var b: Button = _tab_btns[i]
		b.set_pressed_no_signal(i == _active)
	for i in _panels.size():
		var p: Variant = _panels[i]
		if is_instance_valid(p):
			p.visible = i == _active
	_apply_alerts()


## Amber-tint tabs that hold the player's obvious next step.
func _on_sim_stats(_stats: Dictionary) -> void:
	_alert_left -= 0.1
	if _alert_left > 0.0:
		return
	_alert_left = ALERT_POLL_S
	var kaizen := bool(UiUtil.prestige_view().get("can_prestige", false))
	var skills := false
	if UiUtil.game_ready():
		for node in UiUtil.db_list("skills"):
			if typeof(node) != TYPE_DICTIONARY:
				continue
			var st := UiUtil.skill_state(str((node as Dictionary).get("id", "")))
			if bool(st.get("available", false)) and bool(st.get("affordable", false)) and not bool(st.get("purchased", false)):
				skills = true
				break
	if kaizen != _kaizen_alert or skills != _skills_alert:
		_kaizen_alert = kaizen
		_skills_alert = skills
		_apply_alerts()


func _apply_alerts() -> void:
	_set_tab_alert(TAB_SKILLS, _skills_alert and _active != TAB_SKILLS)
	_set_tab_alert(TAB_KAIZEN, _kaizen_alert and _active != TAB_KAIZEN)


func _set_tab_alert(i: int, alert: bool) -> void:
	if i < 0 or i >= _tab_btns.size():
		return
	var b: Button = _tab_btns[i]
	var variation := "TabButtonAlert" if alert else "TabButton"
	if String(b.theme_type_variation) != variation:
		b.theme_type_variation = variation
