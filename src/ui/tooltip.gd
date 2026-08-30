## Tooltip — the one shared tooltip layer for the whole HUD. Any control registers itself
## via attach(control, provider); the provider returns an Array of row dictionaries
## ({"text", "color"?, "size"?, "font_variation"?}) built lazily at show time.
## Shows after 0.4 s hover, on keyboard focus (Steam Deck), and on 0.5 s touch long-press.
extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const Layout = preload("res://src/ui/layout.gd")

const HOVER_DELAY := 0.4
const FOCUS_DELAY := 0.35
const LONGPRESS_DELAY := 0.5
const MAX_WIDTH := 330.0
const MODE_HOVER := 0
const MODE_FOCUS := 1
const MODE_TOUCH := 2

var _panel: PanelContainer
var _rows_box: VBoxContainer
var _providers: Dictionary = {}
var _candidate: Control = null
var _mode := MODE_HOVER
var _timer := 0.0
var _active: Control = null
var _suppressed := false		# onboarding dim up: tooltips must not draw above it
var _layout_mode := Layout.MODE_DESKTOP


## Suppress all tooltips (used while the onboarding overlay dims the screen — this layer
## sits above the dim, so showing anything would punch through it).
func set_suppressed(on: bool) -> void:
	_suppressed = on
	if on:
		_candidate = null
		_hide_tip()


## hud.gd: in the MOBILE layout tooltips come from long-press only (hover is emulated
## noise on touch, and focus tips would pop under stray taps).
func set_layout_mode(mode: int) -> void:
	if _layout_mode == mode:
		return
	_layout_mode = mode
	if mode == Layout.MODE_MOBILE:
		_candidate = null
		_hide_tip()


func _ready() -> void:
	name = "TooltipLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiUtil.full_rect(self)
	_panel = PanelContainer.new()
	_panel.name = "TipPanel"
	_panel.theme_type_variation = "TooltipPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.top_level = false
	add_child(_panel)
	_rows_box = VBoxContainer.new()
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.add_theme_constant_override("separation", 4)
	_panel.add_child(_rows_box)


## Register a control. provider: Callable() -> Array[Dictionary].
func attach(c: Control, provider: Callable) -> void:
	if c == null or _providers.has(c):
		return
	_providers[c] = provider
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.mouse_entered.connect(_on_enter.bind(c))
	c.mouse_exited.connect(_on_leave.bind(c))
	c.focus_entered.connect(_on_focus.bind(c))
	c.focus_exited.connect(_on_leave.bind(c))
	c.gui_input.connect(_on_control_input.bind(c))
	c.visibility_changed.connect(_on_visibility.bind(c))
	c.tree_exiting.connect(detach.bind(c))


func detach(c: Control) -> void:
	_providers.erase(c)
	if _candidate == c:
		_candidate = null
	if _active == c:
		_hide_tip()


## Convenience row builders for providers.
static func row(text: String, color := Color(0, 0, 0, 0), size := 0) -> Dictionary:
	var d := {"text": text}
	if color.a > 0.0:
		d["color"] = color
	if size > 0:
		d["size"] = size
	return d


static func title_row(text: String) -> Dictionary:
	return {"text": text, "color": UiTheme.COL_TEXT, "size": UiTheme.FONT_BODY, "bold": true}


static func dim_row(text: String) -> Dictionary:
	return {"text": text, "color": UiTheme.COL_TEXT_DIM, "size": UiTheme.FONT_SMALL}


static func accent_row(text: String) -> Dictionary:
	return {"text": text, "color": UiTheme.COL_AMBER, "size": UiTheme.FONT_SMALL}


func _process(delta: float) -> void:
	if _candidate != null:
		if not is_instance_valid(_candidate) or not _candidate.is_visible_in_tree():
			_candidate = null
		else:
			_timer -= delta
			if _timer <= 0.0:
				var c := _candidate
				_candidate = null
				_show_for(c)
	if _active != null and _panel.visible:
		if not is_instance_valid(_active) or not _active.is_visible_in_tree():
			_hide_tip()
		elif _mode == MODE_HOVER:
			_place_at(get_global_mouse_position() + Vector2(18.0, 22.0))


func _on_enter(c: Control) -> void:
	_begin(c, MODE_HOVER, HOVER_DELAY)


func _on_focus(c: Control) -> void:
	# Keyboard/controller navigation gets tooltips too (Deck without a mouse).
	_begin(c, MODE_FOCUS, FOCUS_DELAY)


func _on_leave(c: Control) -> void:
	if _candidate == c:
		_candidate = null
	if _active == c:
		_hide_tip()


func _on_visibility(c: Control) -> void:
	if not c.is_visible_in_tree():
		_on_leave(c)


func _on_control_input(event: InputEvent, c: Control) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_begin(c, MODE_TOUCH, LONGPRESS_DELAY)
		else:
			_on_leave(c)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# A click usually changes the underlying values (buy!) — refresh shortly after.
		if _active == c:
			_begin(c, MODE_HOVER, 0.12)


func _begin(c: Control, mode: int, delay: float) -> void:
	if _suppressed or not _providers.has(c):
		return
	if _layout_mode == Layout.MODE_MOBILE and mode != MODE_TOUCH:
		return	# mobile: long-press only
	_candidate = c
	_mode = mode
	_timer = delay


func _show_for(c: Control) -> void:
	if not _providers.has(c) or not is_instance_valid(c):
		return
	var provider: Callable = _providers[c]
	if not provider.is_valid():
		return
	var rows: Variant = provider.call()
	if typeof(rows) != TYPE_ARRAY or (rows as Array).is_empty():
		_hide_tip()
		return
	UiUtil.clear_children(_rows_box)
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var rd: Dictionary = r
		var lbl := Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.text = str(rd.get("text", ""))
		var col: Variant = rd.get("color")
		if typeof(col) == TYPE_COLOR:
			lbl.add_theme_color_override("font_color", col)
		var size: Variant = rd.get("size")
		if typeof(size) == TYPE_INT or typeof(size) == TYPE_FLOAT:
			lbl.add_theme_font_size_override("font_size", int(size))
		if bool(rd.get("bold", false)):
			lbl.add_theme_font_override("font", UiTheme.bold_font())
		_rows_box.add_child(lbl)
		UiUtil.fit_label(lbl, MAX_WIDTH)
	_active = c
	_panel.visible = true
	_panel.reset_size()
	if _mode == MODE_HOVER:
		_place_at(get_global_mouse_position() + Vector2(18.0, 22.0))
	else:
		var r := c.get_global_rect()
		_place_at(Vector2(r.position.x, r.end.y + 6.0))


func _place_at(pos: Vector2) -> void:
	var vp := get_viewport_rect().size
	var sz := _panel.size
	var p := pos
	if p.x + sz.x > vp.x - 4.0:
		p.x = maxf(4.0, vp.x - sz.x - 4.0)
	if p.y + sz.y > vp.y - 4.0:
		p.y = maxf(4.0, pos.y - sz.y - 30.0)
	_panel.position = p


func _hide_tip() -> void:
	_active = null
	_panel.visible = false
