## Effects — folds purchased skill-tree node effects into one modifier bundle and applies
## per-station stat modifiers. Implements the full effect vocabulary pinned in
## docs/ARCHITECTURE.md §7. Pure statics; unknown effect types are ignored with a warning.
extends RefCounted

const STAT_KEYS := ["cycle_time", "uptime", "quality", "capacity", "changeover_time", "operator_count"]


## Neutral bundle (no skills purchased).
static func neutral() -> Dictionary:
	return {
		"global_throughput_mult": 1.0,
		"price_mult": 1.0,
		"upgrade_cost_mult": 1.0,
		"offline_cap_add_hours": 0.0,
		"offline_rate_mult": 1.0,
		"kp_passive_per_min": 0.0,
		"buffer_cap_mult": 1.0,
		"scrap_refund_frac": 0.0,
		"starting_money_add": 0.0,
		"auto_buyer_interval": 0.0,	# 0 = no CI manager; else seconds between greedy buys
		"features": [],	# unlock_feature strings, order of purchase
		"station_mods": {},	# scope key ("all" or station id) -> Array of {stat, op, value}
	}


## Aggregate every effect of every purchased node into one bundle.
## `skill_defs` is db.skills (Array of node dicts), `purchased` maps node id -> true.
static func aggregate(skill_defs: Array, purchased: Dictionary) -> Dictionary:
	var out := neutral()
	for node_v in skill_defs:
		if typeof(node_v) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_v
		if not purchased.has(str(node.get("id", ""))):
			continue
		var effects_v: Variant = node.get("effects", [])
		if typeof(effects_v) != TYPE_ARRAY:
			continue
		for eff_v in effects_v:
			if typeof(eff_v) != TYPE_DICTIONARY:
				continue
			_fold(out, eff_v)
	out["scrap_refund_frac"] = clampf(float(out["scrap_refund_frac"]), 0.0, 1.0)
	return out


static func _fold(out: Dictionary, eff: Dictionary) -> void:
	var type := str(eff.get("type", ""))
	var value: float = float(eff.get("value", 0.0))
	match type:
		"stat_mult":
			_add_station_mod(out, eff, "mul", value)
		"stat_toward_one":
			_add_station_mod(out, eff, "toward_one", value)
		"stat_add":
			_add_station_mod(out, eff, "add", value)
		"global_throughput_mult":
			out["global_throughput_mult"] = float(out["global_throughput_mult"]) * value
		"price_mult":
			out["price_mult"] = float(out["price_mult"]) * value
		"upgrade_cost_mult":
			out["upgrade_cost_mult"] = float(out["upgrade_cost_mult"]) * value
		"offline_cap_add_hours":
			out["offline_cap_add_hours"] = float(out["offline_cap_add_hours"]) + value
		"offline_rate_mult":
			out["offline_rate_mult"] = float(out["offline_rate_mult"]) * value
		"kp_passive_per_min":
			out["kp_passive_per_min"] = float(out["kp_passive_per_min"]) + value
		"buffer_cap_mult":
			out["buffer_cap_mult"] = float(out["buffer_cap_mult"]) * value
		"scrap_refund_frac":
			out["scrap_refund_frac"] = float(out["scrap_refund_frac"]) + value
		"starting_money_add":
			out["starting_money_add"] = float(out["starting_money_add"]) + value
		"auto_buyer":
			var interval: float = max(float(eff.get("interval", 0.0)), 0.1)
			var cur: float = float(out["auto_buyer_interval"])
			out["auto_buyer_interval"] = interval if cur <= 0.0 else minf(cur, interval)
		"unlock_feature":
			var feature := str(eff.get("feature", ""))
			var feats: Array = out["features"]
			if feature != "" and not feats.has(feature):
				feats.append(feature)
		_:
			push_warning("Effects: unknown effect type '%s' ignored" % type)


static func _add_station_mod(out: Dictionary, eff: Dictionary, op: String, value: float) -> void:
	var stat := str(eff.get("stat", ""))
	if not STAT_KEYS.has(stat):
		push_warning("Effects: unknown stat '%s' ignored" % stat)
		return
	var scope := str(eff.get("scope", "all"))
	var key := "all"
	if scope.begins_with("station:"):
		key = scope.substr(8)
	var mods: Dictionary = out["station_mods"]
	if not mods.has(key):
		mods[key] = []
	var lst: Array = mods[key]
	lst.append({"stat": stat, "op": op, "value": value})


## Apply "all"-scoped then station-scoped stat modifiers to a mutable stats dict.
static func apply_station_mods(stats: Dictionary, station_id: String, station_mods: Dictionary) -> void:
	_apply_list(stats, station_mods.get("all", []))
	_apply_list(stats, station_mods.get(station_id, []))


static func _apply_list(stats: Dictionary, mods_v: Variant) -> void:
	if typeof(mods_v) != TYPE_ARRAY:
		return
	for mod_v in mods_v:
		var mod: Dictionary = mod_v
		var stat := str(mod["stat"])
		var cur: float = float(stats.get(stat, 0.0))
		match str(mod["op"]):
			"mul":
				stats[stat] = cur * float(mod["value"])
			"add":
				stats[stat] = cur + float(mod["value"])
			"toward_one":
				stats[stat] = cur + (1.0 - cur) * float(mod["value"])
