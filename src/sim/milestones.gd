## Milestones — evaluates the shared trigger vocabulary (docs/ARCHITECTURE.md §7) for both
## milestones and achievements against a facts dictionary of sim counters. Pure statics.
## Facts keys: lifetime_parts/money_earned (BigNum), pps/oee/zero_scrap_seconds (float),
## bottleneck_cleared_count/upgrade_count/skill_count/prestige_count (int), unlocked_ids (Dict set).
extends RefCounted

const BigNum = preload("res://src/sim/big_num.gd")


## True when `trigger` {type, value} is satisfied by `facts`. Unknown types never trigger.
static func is_triggered(trigger: Dictionary, facts: Dictionary) -> bool:
	var type := str(trigger.get("type", ""))
	var value: Variant = trigger.get("value", 0)
	match type:
		"lifetime_parts":
			return facts["lifetime_parts"].ge(to_bignum(value))
		"money_earned":
			return facts["money_earned"].ge(to_bignum(value))
		"pps":
			return float(facts["pps"]) >= float(value)
		"oee":
			return float(facts["oee"]) >= float(value)
		"bottleneck_cleared_count":
			return int(facts["bottleneck_cleared_count"]) >= int(value)
		"upgrade_count":
			return int(facts["upgrade_count"]) >= int(value)
		"skill_count":
			return int(facts["skill_count"]) >= int(value)
		"prestige_count":
			return int(facts["prestige_count"]) >= int(value)
		"station_unlocked":
			var unlocked: Dictionary = facts["unlocked_ids"]
			return unlocked.has(str(value))
		"zero_scrap_seconds":
			return float(facts["zero_scrap_seconds"]) >= float(value)
		_:
			return false


## Returns the defs (from `pending`) whose trigger fires against `facts`.
static func evaluate(pending: Array, facts: Dictionary) -> Array:
	var hit: Array = []
	for def_v in pending:
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = def_v
		var trigger_v: Variant = def.get("trigger", {})
		if typeof(trigger_v) != TYPE_DICTIONARY:
			continue
		if is_triggered(trigger_v, facts):
			hit.append(def)
	return hit


## Accepts a plain number or a {"m","e"} dict (matching data-file conventions).
static func to_bignum(v: Variant):
	if typeof(v) == TYPE_DICTIONARY:
		return BigNum.from_dict(v)
	return BigNum.from_float(float(v))
