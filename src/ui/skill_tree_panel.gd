## SkillTreePanel — lean skill tree: 5 pinned branch columns (flow/reliability/quality/
## speed/people) from Data.db.skills, node buttons laid out by row with prereq connector
## lines drawn under them. States: purchased / available+affordable (amber pulse) /
## available / locked. Click → Game.buy_skill.
extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")
const TooltipScript = preload("res://src/ui/tooltip.gd")

const NODE_W := 148.0
const NODE_H := 48.0
const COL_GAP := 16.0
const ROW_GAP := 26.0
const HEADER_H := 32.0
const REFRESH_S := 0.3

var _tooltip = null
var _kp_value: Label
var _scroll: ScrollContainer
var _canvas: Control
var _empty_note: Label

var _nodes: Array = []					# skill node defs (dictionaries), file order
var _buttons: Dictionary = {}			# id -> Button
var _rects: Dictionary = {}				# id -> Rect2
var _states: Dictionary = {}			# id -> {purchased, available, affordable, cost}
var _ready_ids: Dictionary = {}			# id -> true (available + affordable)
var _glow_box: StyleBoxFlat
var _pulse_t := 0.0
var _refresh_left := 0.0
var _built_count := -1


func setup(tooltip) -> void:
	_tooltip = tooltip


func _ready() -> void:
	name = "SkillTreePanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var kp_row := HBoxContainer.new()
	v.add_child(kp_row)
	var kp_glyph := Label.new()
	kp_glyph.theme_type_variation = "GlyphLabel"
	kp_glyph.add_theme_color_override("font_color", UiTheme.COL_AMBER)
	kp_glyph.text = "◆"
	kp_row.add_child(kp_glyph)
	var kp_caption := Label.new()
	kp_caption.theme_type_variation = "DimLabel"
	kp_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kp_caption.text = L.t("ui.kaizen_points")
	kp_row.add_child(kp_caption)
	_kp_value = Label.new()
	_kp_value.theme_type_variation = "AccentLabel"
	_kp_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kp_value.text = "0"
	kp_row.add_child(_kp_value)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_canvas = Control.new()
	_canvas.name = "TreeCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_on_canvas_draw)
	_scroll.add_child(_canvas)

	_empty_note = Label.new()
	_empty_note.theme_type_variation = "DimLabel"
	_empty_note.text = L.t("ui.no_data")
	_empty_note.visible = false
	v.add_child(_empty_note)

	_glow_box = UiTheme.flat(Color(0, 0, 0, 0), UiTheme.COL_AMBER, 2, 9, 0.0, 0.0)
	_glow_box.draw_center = false

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.skill_purchased.connect(_on_skill_purchased)
	EventBus.kaizen_points_changed.connect(_on_kp_changed)
	EventBus.game_reset.connect(_rebuild)
	EventBus.load_completed.connect(_rebuild)
	_rebuild()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _ready_ids.is_empty():
		return
	_pulse_t += delta
	_canvas.queue_redraw()


# ---------------------------------------------------------------- build

func _rebuild() -> void:
	_nodes = UiUtil.db_list("skills")
	_built_count = _nodes.size()
	for b in _buttons.values():
		if is_instance_valid(b):
			b.queue_free()
	_buttons.clear()
	_rects.clear()
	_states.clear()
	_ready_ids.clear()
	_empty_note.visible = _nodes.is_empty()
	if _nodes.is_empty():
		return

	var min_row := 2147483647
	for n in _nodes:
		if typeof(n) == TYPE_DICTIONARY:
			min_row = mini(min_row, int((n as Dictionary).get("row", 0)))
	if min_row == 2147483647:
		min_row = 0

	# Branch headers.
	for c in UiUtil.BRANCHES.size():
		var header := Label.new()
		header.theme_type_variation = "DimLabel"
		header.text = L.t("ui.branch_" + str(UiUtil.BRANCHES[c]))
		header.position = Vector2(float(c) * (NODE_W + COL_GAP), 0.0)
		header.custom_minimum_size = Vector2(NODE_W, HEADER_H)
		header.clip_text = true
		_canvas.add_child(header)

	var occupied: Dictionary = {}
	var max_row := 0
	for n in _nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var nd: Dictionary = n
		var nid := str(nd.get("id", ""))
		if nid == "":
			continue
		var col: int = UiUtil.BRANCHES.find(str(nd.get("branch", "")))
		if col < 0:
			col = 0
		var row := int(nd.get("row", 0)) - min_row
		while occupied.has(str(col) + ":" + str(row)):
			row += 1
		occupied[str(col) + ":" + str(row)] = true
		max_row = maxi(max_row, row)
		var rect := Rect2(float(col) * (NODE_W + COL_GAP), HEADER_H + float(row) * (NODE_H + ROW_GAP), NODE_W, NODE_H)
		_rects[nid] = rect

		var b := Button.new()
		b.theme_type_variation = "SkillNode"
		b.text = L.t(str(nd.get("name_key", nid))) + "\n" + UiUtil.kp_amount(nd.get("cost", 0))
		b.clip_text = true
		b.position = rect.position
		b.size = rect.size
		b.pressed.connect(_on_node_pressed.bind(nid))
		_canvas.add_child(b)
		_buttons[nid] = b
		if _tooltip != null:
			_tooltip.attach(b, _tip_node.bind(nid))

	_canvas.custom_minimum_size = Vector2(
		float(UiUtil.BRANCHES.size()) * (NODE_W + COL_GAP) - COL_GAP,
		HEADER_H + float(max_row + 1) * (NODE_H + ROW_GAP))
	_refresh_states()


# ---------------------------------------------------------------- state refresh

func _on_sim_stats(stats: Dictionary) -> void:
	UiUtil.set_label(_kp_value, UiUtil.fmt(stats.get("kp", 0.0)))
	if UiUtil.db_list("skills").size() != _built_count:
		_rebuild()
		return
	if not is_visible_in_tree():
		return
	_refresh_left -= 0.1
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_S
		_refresh_states()


func _on_skill_purchased(_node_id: String) -> void:
	_refresh_states()


func _on_kp_changed(_total: float) -> void:
	_refresh_states()


func _refresh_states() -> void:
	_ready_ids.clear()
	var game_ok := UiUtil.game_ready()
	for n in _nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var nd: Dictionary = n
		var nid := str(nd.get("id", ""))
		var b: Button = _buttons.get(nid)
		if b == null:
			continue
		var st: Dictionary = UiUtil.skill_state(nid) if game_ok else {}
		_states[nid] = st
		var purchased := bool(st.get("purchased", false))
		var available := bool(st.get("available", false))
		var affordable := bool(st.get("affordable", false))
		var variation := "SkillNodeLocked"
		if purchased:
			variation = "SkillNodeOwned"
		elif available and affordable:
			variation = "SkillNodeReady"
			_ready_ids[nid] = true
		elif available:
			variation = "SkillNode"
		if String(b.theme_type_variation) != variation:
			b.theme_type_variation = variation
		var cost_text := L.t("ui.purchased") if purchased else UiUtil.kp_amount(st.get("cost", nd.get("cost", 0)))
		UiUtil.set_btn(b, L.t(str(nd.get("name_key", nid))) + "\n" + cost_text)
	_canvas.queue_redraw()


# ---------------------------------------------------------------- drawing

func _on_canvas_draw() -> void:
	# Prereq connectors (under the buttons).
	for n in _nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var nd: Dictionary = n
		var nid := str(nd.get("id", ""))
		if not _rects.has(nid):
			continue
		var to_rect: Rect2 = _rects[nid]
		var prereqs: Variant = nd.get("prereqs", [])
		if typeof(prereqs) != TYPE_ARRAY:
			continue
		for p in prereqs:
			var pid := str(p)
			if not _rects.has(pid):
				continue
			var from_rect: Rect2 = _rects[pid]
			var from := Vector2(from_rect.position.x + from_rect.size.x * 0.5, from_rect.end.y)
			var to := Vector2(to_rect.position.x + to_rect.size.x * 0.5, to_rect.position.y)
			var pst: Dictionary = _states.get(pid, {})
			var col := UiTheme.COL_GREEN if bool(pst.get("purchased", false)) else UiTheme.COL_BORDER_LIGHT
			if from.x == to.x:
				_canvas.draw_line(from, to, col, 2.0, true)
			else:
				var mid_y := (from.y + to.y) * 0.5
				_canvas.draw_polyline(PackedVector2Array([from, Vector2(from.x, mid_y), Vector2(to.x, mid_y), to]), col, 2.0, true)
	# Amber pulse rings on buyable nodes.
	if _ready_ids.is_empty():
		return
	var alpha := 0.85 if UiUtil.reduce_motion() else 0.35 + 0.5 * (0.5 + 0.5 * sin(_pulse_t * 4.0))
	_glow_box.border_color = Color(UiTheme.COL_AMBER, alpha)
	for nid in _ready_ids:
		if _rects.has(nid):
			var r: Rect2 = _rects[nid]
			_glow_box.draw(_canvas.get_canvas_item(), r.grow(3.0))


# ---------------------------------------------------------------- input / tooltips

func _on_node_pressed(nid: String) -> void:
	if not UiUtil.game_ready():
		return
	var st: Dictionary = _states.get(nid, {})
	if bool(st.get("purchased", false)):
		return
	if UiUtil.game_cmd("buy_skill", [nid]):
		_refresh_states()
	elif AudioDirector.has_method("play"):
		AudioDirector.play("error")


func _find_node(nid: String) -> Dictionary:
	for n in _nodes:
		if typeof(n) == TYPE_DICTIONARY and str((n as Dictionary).get("id", "")) == nid:
			return n
	return {}


func _tip_node(nid: String) -> Array:
	var nd := _find_node(nid)
	if nd.is_empty():
		return []
	var rows: Array = []
	rows.append(TooltipScript.title_row(L.t(str(nd.get("name_key", nid)))))
	var tip_key := str(nd.get("tip_key", ""))
	if tip_key != "":
		rows.append(TooltipScript.dim_row(L.t(tip_key)))
	var effects: Variant = nd.get("effects", [])
	if typeof(effects) == TYPE_ARRAY:
		for e in effects:
			if typeof(e) == TYPE_DICTIONARY:
				rows.append(TooltipScript.row(UiUtil.effect_text(e), UiTheme.COL_GREEN, UiTheme.FONT_SMALL))
	var st: Dictionary = _states.get(nid, {})
	if bool(st.get("purchased", false)):
		rows.append(TooltipScript.row(L.t("ui.purchased"), UiTheme.COL_GREEN, UiTheme.FONT_SMALL))
	else:
		rows.append(TooltipScript.accent_row(L.t("ui.cost") + ": " + UiUtil.kp_amount(st.get("cost", nd.get("cost", 0)))))
		if not bool(st.get("available", true)):
			var names: Array[String] = []
			var prereqs: Variant = nd.get("prereqs", [])
			if typeof(prereqs) == TYPE_ARRAY:
				for p in prereqs:
					var pd := _find_node(str(p))
					if not pd.is_empty():
						names.append(L.t(str(pd.get("name_key", str(p)))))
			if not names.is_empty():
				rows.append(TooltipScript.row(L.t("ui.requires") + ": " + ", ".join(names), UiTheme.COL_RED, UiTheme.FONT_SMALL))
	return rows
