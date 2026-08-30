## Data — loads, normalizes and validates every JSON definition table in src/data/
## (stations, skill tree, milestones, achievements, balance, hints, locale).
## Statics load_all()/validate() are pure and callable without the autoload (tests do);
## the autoload instance fills `Data.db` in _ready() and push_error()s validation failures.
extends Node

const BigNum = preload("res://src/sim/big_num.gd")

const DATA_DIR := "res://src/data/"
const LOCALE_PATH := "res://src/data/locale/en.json"

# Pinned vocabularies (ARCHITECTURE.md section 7). The sim implements exactly these.
const STATION_IDS := ["press", "lathe", "weld", "paint", "assembly", "pack"]
const UPGRADE_IDS := ["speed", "machine", "tooling", "smed"]
const BRANCHES := ["flow", "reliability", "quality", "speed", "people"]
const STAT_NAMES := ["cycle_time", "uptime", "quality", "capacity", "changeover_time", "operator_count"]
const EFFECT_OPS := ["mul", "add", "toward_one"]
const EFFECT_TYPES := [
	"stat_mult", "stat_toward_one", "stat_add", "global_throughput_mult", "price_mult",
	"upgrade_cost_mult", "offline_cap_add_hours", "offline_rate_mult", "kp_passive_per_min",
	"buffer_cap_mult", "scrap_refund_frac", "starting_money_add", "auto_buyer", "unlock_feature",
]
const TRIGGER_TYPES := [
	"lifetime_parts", "money_earned", "pps", "oee", "bottleneck_cleared_count",
	"station_unlocked", "upgrade_count", "skill_count", "prestige_count", "zero_scrap_seconds",
]
const HINT_COND_TYPES := [
	"station_starved_seconds", "bottleneck_stuck_seconds", "affordable_bottleneck_upgrade",
	"kp_unspent", "can_prestige", "always",
]
const ONBOARDING_TARGETS := [
	"world_bottleneck", "bottleneck_card", "fix_button", "top_bar_money", "coach", "skills_tab",
]
const ONBOARDING_ADVANCE := ["next", "on_upgrade"]

var db: Dictionary = {}


func _ready() -> void:
	db = load_all()
	var errors: Array = validate(db)
	for e in errors:
		push_error("Data validation: %s" % str(e))


## Station definition by id ("press".."pack"). Empty Dictionary when unknown.
func station(id: String) -> Dictionary:
	var arr: Array = db.get("stations", [])
	for s_v in arr:
		if typeof(s_v) == TYPE_DICTIONARY and str(s_v.get("id", "")) == id:
			return s_v
	return {}


## Skill node definition by id (e.g. "kanban"). Empty Dictionary when unknown.
func skill(id: String) -> Dictionary:
	var arr: Array = db.get("skills", [])
	for n_v in arr:
		if typeof(n_v) == TYPE_DICTIONARY and str(n_v.get("id", "")) == id:
			return n_v
	return {}


# ---------------------------------------------------------------- loading

## Reads every data file and returns the normalized db Dictionary with keys:
## stations, skills, milestones, achievements, balance, hints (+ locale for validation).
## All money costs (unlock_cost, base_cost) are normalized to BigNum dicts {"m","e"}.
static func load_all() -> Dictionary:
	var out: Dictionary = {}
	out["stations"] = _load_stations()
	out["skills"] = _load_skills()
	out["milestones"] = _load_milestones()
	out["achievements"] = _load_achievements()
	out["balance"] = _load_balance()
	out["hints"] = _load_hints()
	out["orders"] = _load_orders()
	out["onboarding"] = _load_onboarding()
	out["locale"] = _load_locale()
	return out


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed


static func _doc_array(path: String, list_key: String) -> Array:
	var doc: Variant = _read_json(path)
	if typeof(doc) != TYPE_DICTIONARY:
		return []
	var arr: Variant = doc.get(list_key)
	if typeof(arr) != TYPE_ARRAY:
		return []
	return arr


## Normalizes a JSON cost (plain number or {"m","e"}) to a plain float.
## Used for upgrade base_cost, which the sim's cost curves consume as float.
static func _cost_num(v: Variant) -> float:
	if typeof(v) == TYPE_DICTIONARY:
		var dv: Dictionary = v
		if dv.has("m") and dv.has("e"):
			var b = BigNum.make(float(dv["m"]), int(dv["e"]))
			var f: float = b.to_float()
			return f
		return 0.0
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return 0.0


## Normalizes a JSON cost (plain number or {"m","e"}) to a BigNum dict {"m": float, "e": int}.
## Used for unlock_cost, which the sim converts back via BigNum.from_dict.
static func _cost_dict(v: Variant) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		var dv: Dictionary = v
		if dv.has("m") and dv.has("e"):
			var b = BigNum.make(float(dv["m"]), int(dv["e"]))
			var norm: Dictionary = b.to_dict()
			return norm
		return {"m": 0.0, "e": 0}
	var x := 0.0
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		x = float(v)
	var bn = BigNum.from_float(x)
	var out: Dictionary = bn.to_dict()
	return out


static func _load_stations() -> Array:
	var raw: Array = _doc_array(DATA_DIR + "stations.json", "stations")
	var stations: Array = []
	for s_v in raw:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = s_v
		var base_in: Dictionary = {}
		if typeof(s.get("base")) == TYPE_DICTIONARY:
			base_in = s["base"]
		var base: Dictionary = {
			"cycle_time": float(base_in.get("cycle_time", 1.0)),
			"uptime": float(base_in.get("uptime", 1.0)),
			"quality": float(base_in.get("quality", 1.0)),
			"capacity": int(base_in.get("capacity", 1)),
			"changeover_time": float(base_in.get("changeover_time", 0.0)),
			"operator_count": int(base_in.get("operator_count", 1)),
		}
		var upgrades: Dictionary = {}
		var ups_in: Variant = s.get("upgrades")
		if typeof(ups_in) == TYPE_DICTIONARY:
			for track_v in ups_in.keys():
				var u_v: Variant = ups_in[track_v]
				if typeof(u_v) != TYPE_DICTIONARY:
					continue
				var u: Dictionary = u_v
				var eff_in: Dictionary = {}
				if typeof(u.get("effect")) == TYPE_DICTIONARY:
					eff_in = u["effect"]
				upgrades[str(track_v)] = {
					"name_key": str(u.get("name_key", "")),
					"base_cost": _cost_num(u.get("base_cost", 0)),
					"growth": float(u.get("growth", 1.0)),
					"max_level": int(u.get("max_level", 0)),
					"effect": {
						"stat": str(eff_in.get("stat", "")),
						"op": str(eff_in.get("op", "")),
						"value": float(eff_in.get("value", 0.0)),
					},
				}
		stations.append({
			"id": str(s.get("id", "")),
			"name_key": str(s.get("name_key", "")),
			"order": int(s.get("order", 0)),
			"unlock_cost": _cost_dict(s.get("unlock_cost", 0)),
			"base": base,
			"upgrades": upgrades,
		})
	stations.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return stations


static func _load_skills() -> Array:
	var raw: Array = _doc_array(DATA_DIR + "skill_tree.json", "nodes")
	var nodes: Array = []
	for n_v in raw:
		if typeof(n_v) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_v
		var prereqs: Array = []
		var pr_in: Variant = n.get("prereqs")
		if typeof(pr_in) == TYPE_ARRAY:
			for p_v in pr_in:
				prereqs.append(str(p_v))
		var effects: Array = []
		var eff_in: Variant = n.get("effects")
		if typeof(eff_in) == TYPE_ARRAY:
			for e_v in eff_in:
				if typeof(e_v) != TYPE_DICTIONARY:
					continue
				var e: Dictionary = (e_v as Dictionary).duplicate()
				if e.has("value"):
					e["value"] = float(e["value"])
				if e.has("interval"):
					e["interval"] = float(e["interval"])
				effects.append(e)
		nodes.append({
			"id": str(n.get("id", "")),
			"branch": str(n.get("branch", "")),
			"row": int(n.get("row", 0)),
			"name_key": str(n.get("name_key", "")),
			"tip_key": str(n.get("tip_key", "")),
			"cost": int(n.get("cost", 1)),
			"prereqs": prereqs,
			"effects": effects,
		})
	return nodes


static func _normalize_trigger(tr_v: Variant) -> Dictionary:
	if typeof(tr_v) != TYPE_DICTIONARY:
		return {"type": "", "value": 0.0}
	var tr: Dictionary = tr_v
	var ttype := str(tr.get("type", ""))
	var value_v: Variant = tr.get("value", 0)
	if ttype == "station_unlocked":
		return {"type": ttype, "value": str(value_v)}
	var num := 0.0
	if typeof(value_v) == TYPE_FLOAT or typeof(value_v) == TYPE_INT:
		num = float(value_v)
	return {"type": ttype, "value": num}


static func _load_milestones() -> Array:
	var raw: Array = _doc_array(DATA_DIR + "milestones.json", "milestones")
	var milestones: Array = []
	for m_v in raw:
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		milestones.append({
			"id": str(m.get("id", "")),
			"name_key": str(m.get("name_key", "")),
			"kp": int(m.get("kp", 1)),
			"trigger": _normalize_trigger(m.get("trigger")),
		})
	return milestones


static func _load_achievements() -> Array:
	var raw: Array = _doc_array(DATA_DIR + "achievements.json", "achievements")
	var achievements: Array = []
	for a_v in raw:
		if typeof(a_v) != TYPE_DICTIONARY:
			continue
		var a: Dictionary = a_v
		achievements.append({
			"id": str(a.get("id", "")),
			"name_key": str(a.get("name_key", "")),
			"desc_key": str(a.get("desc_key", "")),
			"trigger": _normalize_trigger(a.get("trigger")),
		})
	return achievements


static func _load_balance() -> Dictionary:
	var doc: Variant = _read_json(DATA_DIR + "balance.json")
	if typeof(doc) != TYPE_DICTIONARY:
		return {}
	return doc


static func _load_hints() -> Array:
	var raw: Array = _doc_array(DATA_DIR + "hints.json", "hints")
	var hints: Array = []
	for h_v in raw:
		if typeof(h_v) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_v
		var cond_in: Dictionary = {}
		if typeof(h.get("cond")) == TYPE_DICTIONARY:
			cond_in = h["cond"]
		hints.append({
			"id": str(h.get("id", "")),
			"priority": int(h.get("priority", 0)),
			"cooldown_s": float(h.get("cooldown_s", 60.0)),
			"text_key": str(h.get("text_key", "")),
			"cond": {
				"type": str(cond_in.get("type", "always")),
				"value": cond_in.get("value", true),
			},
		})
	hints.sort_custom(func(a, b): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
	return hints


## Rush-order config: scalar spawn knobs plus normalized templates. {} when absent —
## the sim treats a missing/empty config as "orders disabled".
static func _load_orders() -> Dictionary:
	var doc: Variant = _read_json(DATA_DIR + "orders.json")
	if typeof(doc) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = doc
	var templates: Array = []
	var raw: Variant = d.get("templates")
	if typeof(raw) == TYPE_ARRAY:
		for t_v in raw:
			if typeof(t_v) != TYPE_DICTIONARY:
				continue
			var t: Dictionary = t_v
			templates.append({
				"id": str(t.get("id", "")),
				"name_key": str(t.get("name_key", "")),
				"seconds": float(t.get("seconds", 60.0)),
				"reward_mult": float(t.get("reward_mult", 1.5)),
				"kp_bonus": int(t.get("kp_bonus", 0)),
				"weight": int(t.get("weight", 1)),
			})
	return {
		"schema_version": int(d.get("schema_version", 1)),
		"start_after_seconds": float(d.get("start_after_seconds", 300.0)),
		"cooldown_seconds": float(d.get("cooldown_seconds", 90.0)),
		"min_pps": float(d.get("min_pps", 0.3)),
		"duration_fraction_of_capacity": float(d.get("duration_fraction_of_capacity", 0.7)),
		"templates": templates,
	}


## Onboarding steps (Array, file order = play order). Targets are validated against the
## pinned ONBOARDING_TARGETS list the UI anchors to.
static func _load_onboarding() -> Array:
	var raw: Array = _doc_array(DATA_DIR + "onboarding.json", "steps")
	var steps: Array = []
	for s_v in raw:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = s_v
		steps.append({
			"id": str(s.get("id", "")),
			"target": str(s.get("target", "")),
			"text_key": str(s.get("text_key", "")),
			"advance": str(s.get("advance", "next")),
		})
	return steps


static func _load_locale() -> Dictionary:
	var doc: Variant = _read_json(LOCALE_PATH)
	if typeof(doc) != TYPE_DICTIONARY:
		return {}
	return doc


# ---------------------------------------------------------------- validation

## Validates a db produced by load_all(). Returns human-readable error strings;
## empty array means the data is ship-shape.
static func validate(db_in: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var locale: Dictionary = {}
	var loc_v: Variant = db_in.get("locale")
	if typeof(loc_v) == TYPE_DICTIONARY:
		locale = loc_v
	if locale.is_empty():
		errors.append("locale: en.json missing or empty")
	_validate_stations(db_in, locale, errors)
	_validate_skills(db_in, locale, errors)
	_validate_milestones(db_in, locale, errors)
	_validate_achievements(db_in, locale, errors)
	_validate_hints(db_in, locale, errors)
	_validate_balance(db_in, errors)
	_validate_orders(db_in, locale, errors)
	_validate_onboarding(db_in, locale, errors)
	return errors


static func _need_key(locale: Dictionary, key: String, ctx: String, errors: Array[String]) -> void:
	if key == "":
		errors.append("%s: empty locale key reference" % ctx)
	elif not locale.has(key):
		errors.append("%s: locale missing key '%s'" % [ctx, key])


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _is_cost(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY and v.has("m") and v.has("e")


static func _validate_stations(db_in: Dictionary, locale: Dictionary, errors: Array[String]) -> void:
	var arr_v: Variant = db_in.get("stations")
	if typeof(arr_v) != TYPE_ARRAY:
		errors.append("stations: missing or not an Array")
		return
	var arr: Array = arr_v
	if arr.size() != STATION_IDS.size():
		errors.append("stations: expected %d stations, found %d" % [STATION_IDS.size(), arr.size()])
	var seen_ids: Array = []
	for i in arr.size():
		if typeof(arr[i]) != TYPE_DICTIONARY:
			errors.append("stations[%d]: not a Dictionary" % i)
			continue
		var s: Dictionary = arr[i]
		var sid := str(s.get("id", ""))
		var ctx := "station '%s'" % sid
		if seen_ids.has(sid):
			errors.append("%s: duplicate id" % ctx)
		seen_ids.append(sid)
		if i < STATION_IDS.size() and sid != STATION_IDS[i]:
			errors.append("stations[%d]: expected pinned id '%s', found '%s'" % [i, STATION_IDS[i], sid])
		_need_key(locale, str(s.get("name_key", "")), ctx, errors)
		if not _is_cost(s.get("unlock_cost")):
			errors.append("%s: unlock_cost not normalized to {m,e}" % ctx)
		var base_v: Variant = s.get("base")
		if typeof(base_v) != TYPE_DICTIONARY:
			errors.append("%s: missing base stats" % ctx)
		else:
			var base: Dictionary = base_v
			for stat_name in STAT_NAMES:
				if not base.has(stat_name):
					errors.append("%s: base missing '%s'" % [ctx, stat_name])
			if float(base.get("cycle_time", 0.0)) <= 0.0:
				errors.append("%s: cycle_time must be > 0" % ctx)
			var upt := float(base.get("uptime", 0.0))
			if upt <= 0.0 or upt > 1.0:
				errors.append("%s: uptime must be in (0, 1]" % ctx)
			var qual := float(base.get("quality", 0.0))
			if qual <= 0.0 or qual > 1.0:
				errors.append("%s: quality must be in (0, 1]" % ctx)
			if int(base.get("capacity", 0)) < 1:
				errors.append("%s: capacity must be >= 1" % ctx)
			if float(base.get("changeover_time", -1.0)) < 0.0:
				errors.append("%s: changeover_time must be >= 0" % ctx)
		var ups_v: Variant = s.get("upgrades")
		if typeof(ups_v) != TYPE_DICTIONARY:
			errors.append("%s: missing upgrades" % ctx)
			continue
		var ups: Dictionary = ups_v
		for track in UPGRADE_IDS:
			if not ups.has(track):
				errors.append("%s: missing pinned upgrade track '%s'" % [ctx, track])
		for track_v in ups.keys():
			var track := str(track_v)
			if not UPGRADE_IDS.has(track):
				errors.append("%s: unknown upgrade track '%s'" % [ctx, track])
				continue
			var u: Dictionary = ups[track_v]
			var uctx := "%s upgrade '%s'" % [ctx, track]
			_need_key(locale, str(u.get("name_key", "")), uctx, errors)
			if not _is_num(u.get("base_cost")) or float(u.get("base_cost", 0.0)) <= 0.0:
				errors.append("%s: base_cost not normalized to a positive number" % uctx)
			var growth := float(u.get("growth", 0.0))
			if growth < 1.05 or growth > 1.2:
				errors.append("%s: growth %.3f outside [1.05, 1.2]" % [uctx, growth])
			if int(u.get("max_level", -1)) < 0:
				errors.append("%s: max_level must be >= 0" % uctx)
			var eff_v: Variant = u.get("effect")
			if typeof(eff_v) != TYPE_DICTIONARY:
				errors.append("%s: missing effect" % uctx)
				continue
			var eff: Dictionary = eff_v
			if not STAT_NAMES.has(str(eff.get("stat", ""))):
				errors.append("%s: effect stat '%s' not a station stat" % [uctx, str(eff.get("stat", ""))])
			if not EFFECT_OPS.has(str(eff.get("op", ""))):
				errors.append("%s: effect op '%s' not in %s" % [uctx, str(eff.get("op", "")), str(EFFECT_OPS)])
			if not _is_num(eff.get("value")):
				errors.append("%s: effect value not numeric" % uctx)


static func _validate_effect(e_v: Variant, ctx: String, errors: Array[String]) -> void:
	if typeof(e_v) != TYPE_DICTIONARY:
		errors.append("%s: effect is not a Dictionary" % ctx)
		return
	var e: Dictionary = e_v
	var etype := str(e.get("type", ""))
	if not EFFECT_TYPES.has(etype):
		errors.append("%s: effect type '%s' not in pinned vocabulary" % [ctx, etype])
		return
	if etype == "stat_mult" or etype == "stat_toward_one" or etype == "stat_add":
		if not STAT_NAMES.has(str(e.get("stat", ""))):
			errors.append("%s: %s stat '%s' not a station stat" % [ctx, etype, str(e.get("stat", ""))])
		var scope := str(e.get("scope", ""))
		if scope != "all":
			if not scope.begins_with("station:") or not STATION_IDS.has(scope.trim_prefix("station:")):
				errors.append("%s: %s scope '%s' invalid" % [ctx, etype, scope])
		if not _is_num(e.get("value")):
			errors.append("%s: %s value not numeric" % [ctx, etype])
	elif etype == "auto_buyer":
		if not _is_num(e.get("interval")) or float(e.get("interval", 0.0)) <= 0.0:
			errors.append("%s: auto_buyer interval must be numeric > 0" % ctx)
	elif etype == "unlock_feature":
		if str(e.get("feature", "")) == "":
			errors.append("%s: unlock_feature needs a non-empty feature string" % ctx)
	else:
		if not _is_num(e.get("value")) or float(e.get("value", 0.0)) <= 0.0:
			errors.append("%s: %s value must be numeric > 0" % [ctx, etype])


static func _validate_skills(db_in: Dictionary, locale: Dictionary, errors: Array[String]) -> void:
	var arr_v: Variant = db_in.get("skills")
	if typeof(arr_v) != TYPE_ARRAY:
		errors.append("skills: missing or not an Array")
		return
	var arr: Array = arr_v
	if arr.size() < 44 or arr.size() > 60:
		errors.append("skills: expected 44-60 nodes, found %d" % arr.size())
	var by_id: Dictionary = {}
	for n_v in arr:
		if typeof(n_v) != TYPE_DICTIONARY:
			continue
		var nid := str(n_v.get("id", ""))
		if by_id.has(nid):
			errors.append("skill '%s': duplicate id" % nid)
		by_id[nid] = n_v
	for n_v in arr:
		if typeof(n_v) != TYPE_DICTIONARY:
			errors.append("skills: entry is not a Dictionary")
			continue
		var n: Dictionary = n_v
		var nid := str(n.get("id", ""))
		var ctx := "skill '%s'" % nid
		if nid == "":
			errors.append("skills: node with empty id")
		if not BRANCHES.has(str(n.get("branch", ""))):
			errors.append("%s: branch '%s' not in pinned five" % [ctx, str(n.get("branch", ""))])
		var row := int(n.get("row", -1))
		if row < 0 or row > 8:
			errors.append("%s: row %d outside 0-8" % [ctx, row])
		_need_key(locale, str(n.get("name_key", "")), ctx, errors)
		_need_key(locale, str(n.get("tip_key", "")), ctx, errors)
		var cost := int(n.get("cost", 0))
		if cost < 1 or cost > 15:
			errors.append("%s: cost %d outside 1-15 KP" % [ctx, cost])
		var prereqs_v: Variant = n.get("prereqs")
		if typeof(prereqs_v) != TYPE_ARRAY:
			errors.append("%s: prereqs missing" % ctx)
		else:
			for p_v in prereqs_v:
				var pid := str(p_v)
				if not by_id.has(pid):
					errors.append("%s: prereq '%s' does not exist" % [ctx, pid])
					continue
				var pre: Dictionary = by_id[pid]
				if str(pre.get("branch", "")) != str(n.get("branch", "")):
					errors.append("%s: prereq '%s' crosses branches" % [ctx, pid])
				if int(pre.get("row", 0)) >= row:
					errors.append("%s: prereq '%s' is not in an earlier row" % [ctx, pid])
		var effects_v: Variant = n.get("effects")
		if typeof(effects_v) != TYPE_ARRAY or (effects_v as Array).is_empty():
			errors.append("%s: needs at least one effect" % ctx)
		else:
			for e_v in effects_v:
				_validate_effect(e_v, ctx, errors)


static func _validate_trigger_entry(tr_v: Variant, ctx: String, errors: Array[String]) -> void:
	if typeof(tr_v) != TYPE_DICTIONARY:
		errors.append("%s: trigger missing" % ctx)
		return
	var tr: Dictionary = tr_v
	var ttype := str(tr.get("type", ""))
	if not TRIGGER_TYPES.has(ttype):
		errors.append("%s: trigger type '%s' not in pinned vocabulary" % [ctx, ttype])
		return
	if ttype == "station_unlocked":
		if not STATION_IDS.has(str(tr.get("value", ""))):
			errors.append("%s: station_unlocked value '%s' is not a station id" % [ctx, str(tr.get("value", ""))])
		return
	if not _is_num(tr.get("value")) or float(tr.get("value", 0.0)) <= 0.0:
		errors.append("%s: trigger value must be numeric > 0" % ctx)
	elif ttype == "oee" and float(tr.get("value", 0.0)) > 1.0:
		errors.append("%s: oee trigger value must be <= 1.0" % ctx)


static func _validate_milestones(db_in: Dictionary, locale: Dictionary, errors: Array[String]) -> void:
	var arr_v: Variant = db_in.get("milestones")
	if typeof(arr_v) != TYPE_ARRAY:
		errors.append("milestones: missing or not an Array")
		return
	var arr: Array = arr_v
	if arr.size() < 18 or arr.size() > 28:
		errors.append("milestones: expected 18-28 entries, found %d" % arr.size())
	var seen: Array = []
	for m_v in arr:
		if typeof(m_v) != TYPE_DICTIONARY:
			errors.append("milestones: entry is not a Dictionary")
			continue
		var m: Dictionary = m_v
		var mid := str(m.get("id", ""))
		var ctx := "milestone '%s'" % mid
		if seen.has(mid):
			errors.append("%s: duplicate id" % ctx)
		seen.append(mid)
		_need_key(locale, str(m.get("name_key", "")), ctx, errors)
		var kp := int(m.get("kp", 0))
		if kp < 1 or kp > 5:
			errors.append("%s: kp %d outside 1-5" % [ctx, kp])
		_validate_trigger_entry(m.get("trigger"), ctx, errors)


static func _validate_achievements(db_in: Dictionary, locale: Dictionary, errors: Array[String]) -> void:
	var arr_v: Variant = db_in.get("achievements")
	if typeof(arr_v) != TYPE_ARRAY:
		errors.append("achievements: missing or not an Array")
		return
	var arr: Array = arr_v
	if arr.size() < 28 or arr.size() > 32:
		errors.append("achievements: expected 28-32 entries, found %d" % arr.size())
	var re := RegEx.new()
	re.compile("^ACH_[A-Z0-9_]+$")
	var seen: Array = []
	for a_v in arr:
		if typeof(a_v) != TYPE_DICTIONARY:
			errors.append("achievements: entry is not a Dictionary")
			continue
		var a: Dictionary = a_v
		var aid := str(a.get("id", ""))
		var ctx := "achievement '%s'" % aid
		if re.search(aid) == null:
			errors.append("%s: id does not match ^ACH_[A-Z0-9_]+$" % ctx)
		if seen.has(aid):
			errors.append("%s: duplicate id" % ctx)
		seen.append(aid)
		_need_key(locale, str(a.get("name_key", "")), ctx, errors)
		_need_key(locale, str(a.get("desc_key", "")), ctx, errors)
		_validate_trigger_entry(a.get("trigger"), ctx, errors)


static func _validate_hints(db_in: Dictionary, locale: Dictionary, errors: Array[String]) -> void:
	var arr_v: Variant = db_in.get("hints")
	if typeof(arr_v) != TYPE_ARRAY:
		errors.append("hints: missing or not an Array")
		return
	var arr: Array = arr_v
	if arr.size() < 8 or arr.size() > 12:
		errors.append("hints: expected 8-12 entries, found %d" % arr.size())
	var seen: Array = []
	var last_priority := 0x7FFFFFFF
	for h_v in arr:
		if typeof(h_v) != TYPE_DICTIONARY:
			errors.append("hints: entry is not a Dictionary")
			continue
		var h: Dictionary = h_v
		var hid := str(h.get("id", ""))
		var ctx := "hint '%s'" % hid
		if seen.has(hid):
			errors.append("%s: duplicate id" % ctx)
		seen.append(hid)
		_need_key(locale, str(h.get("text_key", "")), ctx, errors)
		var pr := int(h.get("priority", -1))
		if pr < 0:
			errors.append("%s: priority must be >= 0" % ctx)
		if pr > last_priority:
			errors.append("%s: hints not sorted by priority descending" % ctx)
		last_priority = pr
		if float(h.get("cooldown_s", -1.0)) < 0.0:
			errors.append("%s: cooldown_s must be >= 0" % ctx)
		var cond_v: Variant = h.get("cond")
		if typeof(cond_v) != TYPE_DICTIONARY:
			errors.append("%s: cond missing" % ctx)
		elif not HINT_COND_TYPES.has(str(cond_v.get("type", ""))):
			errors.append("%s: cond type '%s' not in pinned vocabulary" % [ctx, str(cond_v.get("type", ""))])


static func _validate_orders(db_in: Dictionary, locale: Dictionary, errors: Array[String]) -> void:
	var cfg_v: Variant = db_in.get("orders")
	if typeof(cfg_v) != TYPE_DICTIONARY or (cfg_v as Dictionary).is_empty():
		errors.append("orders: missing or empty")
		return
	var cfg: Dictionary = cfg_v
	if not _is_num(cfg.get("start_after_seconds")) or float(cfg.get("start_after_seconds", -1.0)) < 0.0:
		errors.append("orders: start_after_seconds missing or negative")
	if not _is_num(cfg.get("cooldown_seconds")) or float(cfg.get("cooldown_seconds", 0.0)) <= 0.0:
		errors.append("orders: cooldown_seconds missing or not > 0")
	if not _is_num(cfg.get("min_pps")) or float(cfg.get("min_pps", 0.0)) <= 0.0:
		errors.append("orders: min_pps missing or not > 0")
	var frac := 0.0
	if _is_num(cfg.get("duration_fraction_of_capacity")):
		frac = float(cfg.get("duration_fraction_of_capacity"))
	if frac <= 0.0 or frac > 1.0:
		errors.append("orders: duration_fraction_of_capacity must be in (0, 1] — orders must stay beatable")
	var templates_v: Variant = cfg.get("templates")
	if typeof(templates_v) != TYPE_ARRAY:
		errors.append("orders: templates missing or not an Array")
		return
	var templates: Array = templates_v
	if templates.size() < 8 or templates.size() > 10:
		errors.append("orders: expected 8-10 templates, found %d" % templates.size())
	var seen: Array = []
	for t_v in templates:
		if typeof(t_v) != TYPE_DICTIONARY:
			errors.append("orders: template is not a Dictionary")
			continue
		var t: Dictionary = t_v
		var tid := str(t.get("id", ""))
		var ctx := "order '%s'" % tid
		if tid == "":
			errors.append("orders: template with empty id")
		if seen.has(tid):
			errors.append("%s: duplicate id" % ctx)
		seen.append(tid)
		_need_key(locale, str(t.get("name_key", "")), ctx, errors)
		var seconds := float(t.get("seconds", 0.0))
		if seconds < 30.0 or seconds > 600.0:
			errors.append("%s: seconds %.0f outside [30, 600]" % [ctx, seconds])
		var mult := float(t.get("reward_mult", 0.0))
		if mult <= 1.0 or mult > 5.0:
			errors.append("%s: reward_mult %.2f outside (1, 5]" % [ctx, mult])
		var kp_bonus := int(t.get("kp_bonus", -1))
		if kp_bonus < 0 or kp_bonus > 1:
			errors.append("%s: kp_bonus must be 0 or 1" % ctx)
		if int(t.get("weight", 0)) < 1:
			errors.append("%s: weight must be >= 1" % ctx)


static func _validate_onboarding(db_in: Dictionary, locale: Dictionary, errors: Array[String]) -> void:
	var arr_v: Variant = db_in.get("onboarding")
	if typeof(arr_v) != TYPE_ARRAY:
		errors.append("onboarding: missing or not an Array")
		return
	var arr: Array = arr_v
	if arr.size() < 5 or arr.size() > 6:
		errors.append("onboarding: expected 5-6 steps, found %d" % arr.size())
	var seen: Array = []
	var on_upgrade_steps := 0
	for s_v in arr:
		if typeof(s_v) != TYPE_DICTIONARY:
			errors.append("onboarding: step is not a Dictionary")
			continue
		var s: Dictionary = s_v
		var sid := str(s.get("id", ""))
		var ctx := "onboarding step '%s'" % sid
		if sid == "":
			errors.append("onboarding: step with empty id")
		if seen.has(sid):
			errors.append("%s: duplicate id" % ctx)
		seen.append(sid)
		if not ONBOARDING_TARGETS.has(str(s.get("target", ""))):
			errors.append("%s: target '%s' not in pinned target list" % [ctx, str(s.get("target", ""))])
		_need_key(locale, str(s.get("text_key", "")), ctx, errors)
		var adv := str(s.get("advance", ""))
		if not ONBOARDING_ADVANCE.has(adv):
			errors.append("%s: advance '%s' not in %s" % [ctx, adv, str(ONBOARDING_ADVANCE)])
		if adv == "on_upgrade":
			on_upgrade_steps += 1
	if on_upgrade_steps != 1:
		errors.append("onboarding: exactly one step must advance on_upgrade (found %d)" % on_upgrade_steps)


static func _validate_balance(db_in: Dictionary, errors: Array[String]) -> void:
	var bal_v: Variant = db_in.get("balance")
	if typeof(bal_v) != TYPE_DICTIONARY:
		errors.append("balance: missing or not a Dictionary")
		return
	var bal: Dictionary = bal_v
	for key in ["price_per_part", "starting_money", "tick_rate", "buffer_base_cap",
			"changeover_period_seconds", "autosave_seconds"]:
		if not _is_num(bal.get(key)):
			errors.append("balance: pinned key '%s' missing or not numeric" % key)
		elif float(bal.get(key)) <= 0.0 and key != "starting_money":
			errors.append("balance: '%s' must be > 0" % key)
	var offline_v: Variant = bal.get("offline")
	if typeof(offline_v) != TYPE_DICTIONARY:
		errors.append("balance: pinned key 'offline' missing")
	else:
		for key in ["cap_hours_base", "rate", "min_seconds"]:
			if not _is_num(offline_v.get(key)):
				errors.append("balance: offline.%s missing or not numeric" % key)
	var prestige_v: Variant = bal.get("prestige")
	if typeof(prestige_v) != TYPE_DICTIONARY:
		errors.append("balance: pinned key 'prestige' missing")
	else:
		for key in ["min_lifetime_parts", "divisor", "exponent", "multiplier_per_cip"]:
			if not _is_num(prestige_v.get(key)) or float(prestige_v.get(key, 0.0)) <= 0.0:
				errors.append("balance: prestige.%s missing or not > 0" % key)
	var visual_v: Variant = bal.get("visual")
	if typeof(visual_v) != TYPE_DICTIONARY or not _is_num(visual_v.get("part_event_max_pps")):
		errors.append("balance: visual.part_event_max_pps missing or not numeric")
	var pacing_v: Variant = bal.get("pacing")
	if typeof(pacing_v) != TYPE_DICTIONARY:
		errors.append("balance: pinned key 'pacing' missing")
	else:
		var window_v: Variant = pacing_v.get("first_prestige_target_minutes")
		if typeof(window_v) != TYPE_ARRAY or (window_v as Array).size() != 2:
			errors.append("balance: pacing.first_prestige_target_minutes must be [lo, hi]")
		else:
			var window: Array = window_v
			if not _is_num(window[0]) or not _is_num(window[1]) or float(window[0]) >= float(window[1]):
				errors.append("balance: pacing.first_prestige_target_minutes must be ascending numbers")
