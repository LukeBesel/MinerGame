## UiUtil — shared static helpers for the HUD: safe autoload lookup, defensive Game/Data
## accessors, number/duration formatting, status glyphs, and effect descriptions.
## Statics avoid autoload identifiers (main-loop lookup instead) so they compile clean under
## --check-only and stay usable from hermetic tests. No class_name (ARCHITECTURE §2).
extends RefCounted

const BigNum = preload("res://src/sim/big_num.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const UPGRADE_IDS := ["speed", "machine", "tooling", "smed"]
const BRANCHES := ["flow", "reliability", "quality", "speed", "people"]


# ---------------------------------------------------------------- autoload access

## Resolve an autoload by name without referencing its identifier (null when absent).
static func autoload(node_name: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var root: Window = (ml as SceneTree).root
		if root != null:
			return root.get_node_or_null(NodePath(node_name))
	return null


## True once the sim exists (Game.sim != null). Every command/view path checks this.
static func game_ready() -> bool:
	var g := autoload("Game")
	return g != null and ("sim" in g) and g.get("sim") != null


## Call a Game method if it exists (and return its result), else null. Does NOT check
## game_ready() — command helpers below do.
static func game_call(method: String, args: Array = []) -> Variant:
	var g := autoload("Game")
	if g != null and g.has_method(method):
		return g.callv(method, args)
	return null


## Guarded command: no-op returning false until Game.sim exists and the method is shipped.
static func game_cmd(method: String, args: Array = []) -> bool:
	if not game_ready():
		return false
	var r: Variant = game_call(method, args)
	return r == true


static func game_dict(method: String, args: Array = []) -> Dictionary:
	if not game_ready():
		return {}
	var r: Variant = game_call(method, args)
	if typeof(r) == TYPE_DICTIONARY:
		return r
	return {}


static func upgrade_view(station: int, uid: String) -> Dictionary:
	return game_dict("get_upgrade_view", [station, uid])


static func prestige_view() -> Dictionary:
	return game_dict("get_prestige_view")


static func skill_state(node_id: String) -> Dictionary:
	return game_dict("get_skill_state", [node_id])


static func stats_snapshot() -> Dictionary:
	return game_dict("get_stats_snapshot")


## Data.db (or {} while the data module is not shipped).
static func db() -> Dictionary:
	var d := autoload("Data")
	if d != null and ("db" in d):
		var v: Variant = d.get("db")
		if typeof(v) == TYPE_DICTIONARY:
			return v
	return {}


static func db_list(key: String) -> Array:
	var v: Variant = db().get(key, [])
	if typeof(v) == TYPE_ARRAY:
		return v
	return []


# ---------------------------------------------------------------- settings

static func number_mode() -> String:
	var ss := autoload("SettingsService")
	if ss != null and ("number_format" in ss):
		var v: Variant = ss.get("number_format")
		if typeof(v) == TYPE_STRING and str(v) != "":
			return str(v)
	return "suffix"


static func reduce_motion() -> bool:
	var ss := autoload("SettingsService")
	if ss != null and ("reduce_motion" in ss):
		return bool(ss.get("reduce_motion"))
	return false


static func setting(key: String, def: Variant) -> Variant:
	var ss := autoload("SettingsService")
	if ss != null and (key in ss):
		var v: Variant = ss.get(key)
		if v != null:
			return v
	return def


# ---------------------------------------------------------------- localization wrappers

static func tr_key(key: String) -> String:
	var l := autoload("L")
	if l != null and l.has_method("t"):
		return str(l.call("t", key))
	return key


static func trf(key: String, args: Array) -> String:
	var l := autoload("L")
	if l != null and l.has_method("tf"):
		return str(l.call("tf", key, args))
	return key


## Template with a symbol-only fallback (used for unit/currency glyph templates so money
## never renders as a raw key while the locale table is still being authored).
static func trf_or(key: String, args: Array, fallback: String) -> String:
	var l := autoload("L")
	if l != null and l.has_method("has_key") and bool(l.call("has_key", key)) and l.has_method("tf"):
		return str(l.call("tf", key, args))
	return fallback


# ---------------------------------------------------------------- number formatting

## Format a BigNum object, a {"m":..,"e":..} dict, or a plain number with the user's mode.
static func fmt_mode(v: Variant, mode: String) -> String:
	if typeof(v) == TYPE_OBJECT and v != null:
		var o: Object = v
		if o.has_method("format"):
			return str(o.call("format", mode))
	if typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("m"):
		var b = BigNum.from_dict(v)
		return str(b.format(mode))
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		var b2 = BigNum.from_float(float(v))
		return str(b2.format(mode))
	return str(v)


static func fmt(v: Variant) -> String:
	return fmt_mode(v, number_mode())


static func money(v: Variant) -> String:
	var s := fmt(v)
	return trf_or("ui.money_amount", [s], "$" + s)


static func per_sec(v: Variant) -> String:
	# ui.per_sec is a plain suffix ("/s"), not a {0} template.
	var s := fmt(v)
	var l := autoload("L")
	if l != null and l.has_method("has_key") and bool(l.call("has_key", "ui.per_sec")):
		return s + str(l.call("t", "ui.per_sec"))
	return s + "/s"


static func kp_amount(v: Variant) -> String:
	var s := fmt(v)
	return trf_or("ui.kp_amount", [s], s + " KP")


static func mult_x(v: float) -> String:
	var s := trim_float(v)
	return trf_or("ui.mult_value", [s], "×" + s)


static func pct(x: float) -> String:
	return str(int(roundf(clampf(x, 0.0, 99.99) * 100.0))) + "%"


static func trim_float(v: float) -> String:
	var s := "%.2f" % v
	if s.contains("."):
		while s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s


## "+5%" / "-7%" from a per-level multiplier like 1.05 / 0.93.
static func signed_pct_from_mult(v: float) -> String:
	var delta := (v - 1.0) * 100.0
	var s := trim_float(delta)
	if delta >= 0.0:
		s = "+" + s
	return s + "%"


## Compact "2h 05m" / "4m 12s" / "42s" style duration.
static func duration(seconds: float) -> String:
	var s := int(maxf(seconds, 0.0))
	var h := int(floorf(float(s) / 3600.0))
	var m := int(floorf(float(s % 3600) / 60.0))
	var sec := s % 60
	var parts: Array[String] = []
	if h > 0:
		parts.append(trf_or("ui.dur_h", [h], str(h) + "h"))
	if m > 0 or h > 0:
		parts.append(trf_or("ui.dur_m", [m], str(m) + "m"))
	if h == 0:
		parts.append(trf_or("ui.dur_s", [sec], str(sec) + "s"))
	return " ".join(parts)


# ---------------------------------------------------------------- station status

## Colorblind-safe status telegraphing: icon + color, mirroring the 3D world (§8).
static func status_glyph(status: int, is_bottleneck: bool) -> String:
	if is_bottleneck:
		return "!"
	match status:
		SimTypes.STATUS_STARVED:
			return "Zz"
		SimTypes.STATUS_BLOCKED:
			return "■"
		SimTypes.STATUS_RUNNING:
			return "●"
	return "○"


static func status_color(status: int, is_bottleneck: bool) -> Color:
	if is_bottleneck:
		return UiTheme.COL_RED
	match status:
		SimTypes.STATUS_STARVED:
			return UiTheme.COL_GREY
		SimTypes.STATUS_BLOCKED:
			return UiTheme.COL_AMBER
		SimTypes.STATUS_RUNNING:
			return UiTheme.COL_GREEN
	return UiTheme.COL_TEXT_DISABLED


static func status_name(status: int, is_bottleneck: bool) -> String:
	if is_bottleneck:
		return tr_key("ui.bottleneck")
	match status:
		SimTypes.STATUS_STARVED:
			return tr_key("ui.starved")
		SimTypes.STATUS_BLOCKED:
			return tr_key("ui.blocked")
		SimTypes.STATUS_RUNNING:
			return tr_key("ui.running")
	return tr_key("ui.idle")


# ---------------------------------------------------------------- data lookups

## Localized display name for a station id via Data.db (falls back to the id).
static func station_display_name(sid: String) -> String:
	for s in db_list("stations"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == sid:
			return tr_key(str(s.get("name_key", sid)))
	return sid


static func station_def(index: int) -> Dictionary:
	var arr := db_list("stations")
	if index >= 0 and index < arr.size() and typeof(arr[index]) == TYPE_DICTIONARY:
		return arr[index]
	return {}


static func upgrade_def(station_index: int, uid: String) -> Dictionary:
	var ups: Variant = station_def(station_index).get("upgrades", {})
	if typeof(ups) == TYPE_DICTIONARY:
		var u: Variant = (ups as Dictionary).get(uid, {})
		if typeof(u) == TYPE_DICTIONARY:
			return u
	return {}


static func upgrade_display_name(station_index: int, uid: String) -> String:
	var u := upgrade_def(station_index, uid)
	var key := str(u.get("name_key", "upgrade." + uid))
	return tr_key(key)


# ---------------------------------------------------------------- effect descriptions

static func stat_name(stat: String) -> String:
	match stat:
		"quality":
			return tr_key("ui.quality")
		"uptime":
			return tr_key("ui.uptime")
		"changeover_time":
			return tr_key("ui.changeover")
		"cycle_time":
			return tr_key("ui.cycle_time")
		"capacity":
			return tr_key("ui.capacity")
		"operator_count":
			return tr_key("ui.operators")
	return stat


static func scope_text(e: Dictionary) -> String:
	var s := str(e.get("scope", "all"))
	if s.begins_with("station:"):
		return trf("ui.scope_station", [station_display_name(s.substr(8))])
	return tr_key("ui.scope_all")


## One human-readable line for a skill-effect dictionary (§7 effect vocabulary).
static func effect_text(e: Dictionary) -> String:
	var t := str(e.get("type", ""))
	var vv: Variant = e.get("value", 0)
	var v := 0.0
	if typeof(vv) == TYPE_FLOAT or typeof(vv) == TYPE_INT:
		v = float(vv)
	match t:
		"stat_mult":
			return trf("ui.effect_stat_mult", [stat_name(str(e.get("stat", ""))), signed_pct_from_mult(v), scope_text(e)])
		"stat_toward_one":
			return trf("ui.effect_stat_toward_one", [stat_name(str(e.get("stat", ""))), trim_float(v * 100.0) + "%", scope_text(e)])
		"stat_add":
			return trf("ui.effect_stat_add", [stat_name(str(e.get("stat", ""))), trim_float(v), scope_text(e)])
		"global_throughput_mult":
			return trf("ui.effect_global_throughput_mult", [signed_pct_from_mult(v)])
		"price_mult":
			return trf("ui.effect_price_mult", [signed_pct_from_mult(v)])
		"upgrade_cost_mult":
			return trf("ui.effect_upgrade_cost_mult", [signed_pct_from_mult(v)])
		"offline_cap_add_hours":
			return trf("ui.effect_offline_cap_add_hours", [trim_float(v)])
		"offline_rate_mult":
			return trf("ui.effect_offline_rate_mult", [signed_pct_from_mult(v)])
		"kp_passive_per_min":
			return trf("ui.effect_kp_passive_per_min", [trim_float(v)])
		"buffer_cap_mult":
			return trf("ui.effect_buffer_cap_mult", [signed_pct_from_mult(v)])
		"scrap_refund_frac":
			return trf("ui.effect_scrap_refund_frac", [trim_float(v * 100.0) + "%"])
		"starting_money_add":
			return trf("ui.effect_starting_money_add", [trim_float(v)])
		"auto_buyer":
			return trf("ui.effect_auto_buyer", [trim_float(float(e.get("interval", 0.0)))])
		"unlock_feature":
			return trf("ui.effect_unlock_feature", [str(e.get("feature", ""))])
	return t


## One line for a station-upgrade effect ({stat, op: mul|add|toward_one, value}, §7).
static func upgrade_effect_text(e: Dictionary) -> String:
	var stat := stat_name(str(e.get("stat", "")))
	var vv: Variant = e.get("value", 0)
	var v := 0.0
	if typeof(vv) == TYPE_FLOAT or typeof(vv) == TYPE_INT:
		v = float(vv)
	match str(e.get("op", "")):
		"mul":
			return trf("ui.upeffect_mul", [stat, signed_pct_from_mult(v)])
		"add":
			return trf("ui.upeffect_add", [stat, "+" + trim_float(v)])
		"toward_one":
			return trf("ui.upeffect_toward_one", [stat, trim_float(v * 100.0) + "%"])
	return stat


# ---------------------------------------------------------------- small UI helpers

static func set_label(l: Label, s: String) -> void:
	if l != null and l.text != s:
		l.text = s


static func set_btn(b: Button, s: String) -> void:
	if b != null and b.text != s:
		b.text = s


## Explicit anchors+offsets. Never use set_anchors_preset on a control already in the
## tree: with keep_offsets=false it rewrites offsets to preserve the current (often 0×0)
## rect, silently collapsing "full rect" layers to zero size.
static func anchor_box(c: Control, al: float, at: float, ar: float, ab: float, ol := 0.0, ot := 0.0, orr := 0.0, ob := 0.0) -> void:
	if c == null:
		return
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


static func full_rect(c: Control) -> void:
	anchor_box(c, 0.0, 0.0, 1.0, 1.0)


## Enforce the 36 px minimum touch/click target (Steam Deck).
static func min_touch(c: Control, w := 0.0) -> void:
	if c != null:
		c.custom_minimum_size = Vector2(maxf(c.custom_minimum_size.x, w), maxf(c.custom_minimum_size.y, UiTheme.TOUCH_MIN))


## Size a label naturally, wrapping only once it would exceed max_w. Call after add_child.
static func fit_label(l: Label, max_w: float) -> void:
	if l == null:
		return
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2.ZERO
	if l.get_minimum_size().x > max_w:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(max_w, 0)


static func clear_children(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
