## StatsPanel — lifetime numbers tab: lifetime parts, total scrap, time played, prestige
## count, current multiplier, and a per-station throughput table. Renders from sim_stats.
extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiUtil = preload("res://src/ui/ui_util.gd")

const REFRESH_S := 0.5

var _rows: Dictionary = {}			# key -> value Label
var _table: GridContainer
var _table_cells: Array = []		# per station: {name, thr, q}
var _refresh_left := 0.0
var _last_stats: Dictionary = {}


func _ready() -> void:
	name = "StatsPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = L.t("ui.tab_stats")
	v.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	_add_stat_row(grid, "lifetime_parts", "ui.stats_lifetime_parts")
	_add_stat_row(grid, "scrap_total", "ui.stats_scrap")
	_add_stat_row(grid, "time_played", "ui.stats_time_played")
	_add_stat_row(grid, "prestige_count", "ui.stats_prestige_count")
	_add_stat_row(grid, "cip", "ui.cip")
	_add_stat_row(grid, "cip_mult", "ui.stats_multiplier")
	_add_stat_row(grid, "kp", "ui.kaizen_points")

	var sep := HSeparator.new()
	v.add_child(sep)

	var table_title := Label.new()
	table_title.theme_type_variation = "TitleLabel"
	table_title.text = L.t("ui.stats_stations")
	v.add_child(table_title)

	_table = GridContainer.new()
	_table.columns = 3
	_table.add_theme_constant_override("v_separation", 6)
	_table.add_theme_constant_override("h_separation", 16)
	v.add_child(_table)

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.game_reset.connect(_refresh_once)
	EventBus.load_completed.connect(_refresh_once)
	_refresh_once()


func _add_stat_row(grid: GridContainer, key: String, label_key: String) -> void:
	var caption := Label.new()
	caption.theme_type_variation = "DimLabel"
	caption.text = L.t(label_key)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(caption)
	var value := Label.new()
	value.theme_type_variation = "ValueLabel"
	value.text = "—"
	grid.add_child(value)
	_rows[key] = value


func _refresh_once() -> void:
	var stats := UiUtil.stats_snapshot()
	if not stats.is_empty():
		_last_stats = stats
		_render()


func _on_sim_stats(stats: Dictionary) -> void:
	_last_stats = stats
	if not is_visible_in_tree():
		return
	_refresh_left -= 0.1
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_S
		_render()


func _render() -> void:
	var stats := _last_stats
	if stats.is_empty():
		return
	_set_row("lifetime_parts", UiUtil.fmt(stats.get("lifetime_parts", 0.0)))
	_set_row("scrap_total", UiUtil.fmt(stats.get("scrap_total", 0.0)))
	_set_row("time_played", UiUtil.duration(float(stats.get("time_played", 0.0))))
	_set_row("prestige_count", str(int(stats.get("prestige_count", 0))))
	_set_row("cip", UiUtil.fmt(stats.get("cip", 0)))
	_set_row("cip_mult", UiUtil.mult_x(float(stats.get("cip_mult", 1.0))))
	_set_row("kp", UiUtil.fmt(stats.get("kp", 0.0)))
	_render_table(stats)


func _set_row(key: String, text: String) -> void:
	var l: Label = _rows.get(key)
	UiUtil.set_label(l, text)


func _render_table(stats: Dictionary) -> void:
	var stations_v: Variant = stats.get("stations", [])
	if typeof(stations_v) != TYPE_ARRAY:
		return
	var stations: Array = stations_v
	if _table_cells.size() != stations.size():
		_build_table(stations.size())
	for i in stations.size():
		var view_v: Variant = stations[i]
		if typeof(view_v) != TYPE_DICTIONARY:
			continue
		var view: Dictionary = view_v
		var cells: Dictionary = _table_cells[i]
		var unlocked := bool(view.get("unlocked", false))
		UiUtil.set_label(cells["name"], str(view.get("name", str(i))))
		if unlocked:
			UiUtil.set_label(cells["thr"], UiUtil.per_sec(view.get("throughput", 0.0)))
			var q := 0.0
			var s: Variant = view.get("stats", {})
			if typeof(s) == TYPE_DICTIONARY:
				q = float((s as Dictionary).get("quality", 0.0))
			UiUtil.set_label(cells["q"], UiUtil.pct(q))
		else:
			UiUtil.set_label(cells["thr"], L.t("ui.locked"))
			UiUtil.set_label(cells["q"], "—")
		var col := UiTheme.COL_TEXT if unlocked else UiTheme.COL_TEXT_DISABLED
		(cells["name"] as Label).add_theme_color_override("font_color", col)


func _build_table(n: int) -> void:
	UiUtil.clear_children(_table)
	_table_cells.clear()
	for header_key in ["ui.station", "ui.throughput", "ui.quality"]:
		var h := Label.new()
		h.theme_type_variation = "TinyLabel"
		h.text = L.t(str(header_key))
		_table.add_child(h)
	for i in n:
		var name_l := Label.new()
		name_l.theme_type_variation = "Label"
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_table.add_child(name_l)
		var thr_l := Label.new()
		thr_l.theme_type_variation = "Label"
		_table.add_child(thr_l)
		var q_l := Label.new()
		q_l.theme_type_variation = "Label"
		_table.add_child(q_l)
		_table_cells.append({"name": name_l, "thr": thr_l, "q": q_l})
