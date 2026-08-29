## Autoplayer — shared inline fixture db + greedy bot driving a pure SimEngine (no autoloads).
## Every `decision_interval` sim-seconds it buys the best delta-revenue-rate/cost purchase
## among affordable upgrades/unlocks, spends KP on the cheapest available skill, and stops at
## the first prestige. Collects a log of [sim_time, event_id] tuples for pacing analysis.
extends RefCounted

const SimEngineScript = preload("res://src/sim/sim_engine.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const BigNum = preload("res://src/sim/big_num.gd")

const PROGRESS_EVENT_TYPES := ["station_unlocked", "milestone_reached", "skill_purchased", "achievement_unlocked"]

var engine = null
var sim_time: float = 0.0
var event_log: Array = []	# [ [sim_time: float, event_id: String], ... ]
var prestiged: bool = false
var prestige_time: float = -1.0


# ------------------------------------------------------------------ fixture db

## Small hermetic db for unit tests: 3 unlocked stations (beta is the 0.4 pps bottleneck,
## quality 0.8) + locked delta, every effect type in the skill list, every trigger type in
## the milestones. Returns a fresh deep structure on every call — tests may mutate freely.
static func fixture_db() -> Dictionary:
	return {
		"stations": [
			_station("alpha", 0, 0, {"cycle_time": 1.0, "uptime": 1.0, "quality": 1.0,
					"capacity": 1, "changeover_time": 0.0, "operator_count": 1}),
			_station("beta", 1, 0, {"cycle_time": 2.0, "uptime": 1.0, "quality": 0.8,
					"capacity": 1, "changeover_time": 0.0, "operator_count": 1}),
			_station("gamma", 2, 0, {"cycle_time": 1.0, "uptime": 1.0, "quality": 1.0,
					"capacity": 1, "changeover_time": 0.0, "operator_count": 1}),
			_station("delta", 3, 50, {"cycle_time": 0.5, "uptime": 1.0, "quality": 1.0,
					"capacity": 1, "changeover_time": 0.0, "operator_count": 1}),
		],
		"skills": [
			_skill("s_global", 1, [], [{"type": "global_throughput_mult", "value": 2.0}]),
			_skill("s_price", 1, [], [{"type": "price_mult", "value": 3.0}]),
			_skill("s_cost", 1, [], [{"type": "upgrade_cost_mult", "value": 0.5}]),
			_skill("s_capadd", 1, ["s_global"],
					[{"type": "stat_add", "stat": "capacity", "scope": "station:alpha", "value": 2}]),
			_skill("s_upall", 2, [],
					[{"type": "stat_mult", "stat": "cycle_time", "scope": "all", "value": 0.5}]),
			_skill("s_q1", 1, [],
					[{"type": "stat_toward_one", "stat": "quality", "scope": "station:beta", "value": 1.0}]),
			_skill("s_offcap", 1, [], [{"type": "offline_cap_add_hours", "value": 4.0}]),
			_skill("s_offrate", 1, [], [{"type": "offline_rate_mult", "value": 2.0}]),
			_skill("s_kp", 1, [], [{"type": "kp_passive_per_min", "value": 60.0}]),
			_skill("s_buf", 1, [], [{"type": "buffer_cap_mult", "value": 0.5}]),
			_skill("s_refund", 1, [], [{"type": "scrap_refund_frac", "value": 0.5}]),
			_skill("s_start", 1, [], [{"type": "starting_money_add", "value": 500.0}]),
			_skill("s_auto", 1, [], [{"type": "auto_buyer", "interval": 1.0}]),
			_skill("s_feat", 1, [], [{"type": "unlock_feature", "feature": "conveyor_vision"}]),
		],
		"milestones": [
			_milestone("m_parts_10", 2, {"type": "lifetime_parts", "value": 10}),
			_milestone("m_money_50", 1, {"type": "money_earned", "value": 50}),
			_milestone("m_pps", 1, {"type": "pps", "value": 0.3}),
			_milestone("m_oee", 1, {"type": "oee", "value": 0.2}),
			_milestone("m_bnc", 1, {"type": "bottleneck_cleared_count", "value": 1}),
			_milestone("m_unlock_delta", 3, {"type": "station_unlocked", "value": "delta"}),
			_milestone("m_upg5", 1, {"type": "upgrade_count", "value": 5}),
			_milestone("m_skill2", 1, {"type": "skill_count", "value": 2}),
			_milestone("m_prest1", 5, {"type": "prestige_count", "value": 1}),
			_milestone("m_zeroscrap", 1, {"type": "zero_scrap_seconds", "value": 5}),
		],
		"achievements": [
			{"id": "ACH_FIRST_PART", "name_key": "ach.first", "desc_key": "ach.first.d",
					"trigger": {"type": "lifetime_parts", "value": 1}},
			{"id": "ACH_UNLOCK_DELTA", "name_key": "ach.delta", "desc_key": "ach.delta.d",
					"trigger": {"type": "station_unlocked", "value": "delta"}},
		],
		"balance": {
			"schema_version": 1,
			"price_per_part": 1.0,
			"starting_money": 100.0,
			"tick_rate": 10,
			"buffer_base_cap": 10.0,
			"changeover_period_seconds": 600.0,
			"offline": {"cap_hours_base": 8.0, "rate": 1.0, "min_seconds": 60.0},
			"prestige": {"min_lifetime_parts": 1000.0, "divisor": 100.0, "exponent": 0.5,
					"multiplier_per_cip": 0.10},
			"autosave_seconds": 30,
			"visual": {"part_event_max_pps": 8.0},
			"pacing": {"first_prestige_target_minutes": [25.0, 50.0]},
		},
	}


static func _station(id: String, order: int, unlock_cost: Variant, base: Dictionary) -> Dictionary:
	return {
		"id": id, "name_key": "station.%s" % id, "order": order, "unlock_cost": unlock_cost,
		"base": base,
		"upgrades": {
			"speed": {"name_key": "upgrade.speed", "base_cost": 10.0, "growth": 1.10,
					"effect": {"stat": "cycle_time", "op": "mul", "value": 0.9}, "max_level": 0},
			"machine": {"name_key": "upgrade.machine", "base_cost": 25.0, "growth": 1.15,
					"effect": {"stat": "capacity", "op": "add", "value": 1}, "max_level": 4},
			"tooling": {"name_key": "upgrade.tooling", "base_cost": 15.0, "growth": 1.12,
					"effect": {"stat": "quality", "op": "toward_one", "value": 0.5}, "max_level": 10},
			"smed": {"name_key": "upgrade.smed", "base_cost": 20.0, "growth": 1.12,
					"effect": {"stat": "changeover_time", "op": "mul", "value": 0.5}, "max_level": 5},
		},
	}


static func _skill(id: String, cost: int, prereqs: Array, effects: Array) -> Dictionary:
	return {"id": id, "branch": "flow", "row": 1, "name_key": "skill.%s" % id,
			"tip_key": "skill.%s.tip" % id, "cost": cost, "prereqs": prereqs, "effects": effects}


static func _milestone(id: String, kp: int, trigger: Dictionary) -> Dictionary:
	return {"id": id, "name_key": "ms.%s" % id, "kp": kp, "trigger": trigger}


# ------------------------------------------------------------------ bot

## Run the greedy bot on `db` until first prestige or `max_sim_seconds`. Returns a summary.
func run(db: Dictionary, max_sim_seconds: float, decision_interval: float = 5.0) -> Dictionary:
	engine = SimEngineScript.new_game(db)
	sim_time = 0.0
	event_log = []
	prestiged = false
	prestige_time = -1.0
	var dt: float = SimTypes.TICK_DT
	var ticks_per_window: int = maxi(int(roundf(decision_interval / dt)), 1)
	while sim_time < max_sim_seconds and not prestiged:
		for _i in ticks_per_window:
			engine.tick(dt)
			sim_time += dt
			if sim_time >= max_sim_seconds:
				break
		_collect_events()
		_decide()
	_collect_events()
	return {
		"prestiged": prestiged,
		"prestige_time": prestige_time,
		"log": event_log,
		"sim_time": sim_time,
	}


func _collect_events() -> void:
	var events: Array = engine.drain_events()
	for ev_v in events:
		var ev: Dictionary = ev_v
		event_log.append([sim_time, _event_id(ev)])


func _event_id(ev: Dictionary) -> String:
	var t := str(ev.get("t", ""))
	match t:
		"milestone_reached", "achievement_unlocked":
			return "%s:%s" % [t, str(ev.get("id", ""))]
		"skill_purchased":
			return "%s:%s" % [t, str(ev.get("node_id", ""))]
		"station_unlocked", "station_upgraded", "part_completed", "scrap_produced", \
		"station_status_changed", "bottleneck_cleared":
			return "%s:%s" % [t, str(ev.get("station", ""))]
		"bottleneck_changed":
			return "%s:%s->%s" % [t, str(ev.get("old_index", "")), str(ev.get("new_index", ""))]
		_:
			return t


func _decide() -> void:
	# 1. Prestige ends the run.
	var pv: Dictionary = engine.get_prestige_view()
	if bool(pv["can_prestige"]):
		if engine.do_prestige():
			prestiged = true
			prestige_time = sim_time
			_collect_events()
		return
	# 2. Spend KP on the cheapest available skill(s).
	var bought := true
	while bought:
		bought = false
		var best_id := ""
		var best_cost: int = 0
		for def_v in engine.skills_def:
			var def: Dictionary = def_v
			var id := str(def.get("id", ""))
			var st: Dictionary = engine.get_skill_state(id)
			if bool(st["available"]) and bool(st["affordable"]):
				if best_id == "" or int(st["cost"]) < best_cost:
					best_id = id
					best_cost = int(st["cost"])
		if best_id != "" and engine.buy_skill(best_id):
			bought = true
			_collect_events()
	# 3. One purchase: best delta-revenue-rate per cost among affordable upgrades/unlocks.
	var best_kind := ""
	var best_station: int = -1
	var best_uid := ""
	var best_score = null	# BigNum
	for i in engine.stations_def.size():
		var view: Dictionary = engine.get_station_view(i)
		if not bool(view["unlocked"]):
			continue
		for uid in ["speed", "machine", "tooling", "smed"]:
			var uv: Dictionary = engine.get_upgrade_view(i, uid, 1)
			if bool(uv["maxed"]) or not bool(uv["affordable"]):
				continue
			var delta: float = engine.estimate_upgrade_delta_rps(i, uid)
			if delta <= 0.0:
				continue
			var score = BigNum.from_float(delta).div(uv["cost"])
			if best_score == null or score.gt(best_score):
				best_score = score
				best_kind = "upgrade"
				best_station = i
				best_uid = uid
	var next_locked: int = engine.next_locked_index()
	if next_locked >= 0:
		var lview: Dictionary = engine.get_station_view(next_locked)
		var ucost = lview["unlock_cost"]
		if engine.money.ge(ucost):
			var udelta: float = engine.estimate_unlock_delta_rps(next_locked)
			if udelta > 0.0:
				var uscore = BigNum.from_float(udelta).div(ucost)
				if best_score == null or uscore.gt(best_score):
					best_score = uscore
					best_kind = "unlock"
					best_station = next_locked
	if best_kind == "upgrade":
		engine.buy_upgrade(best_station, best_uid, 1)
		_collect_events()
	elif best_kind == "unlock":
		engine.unlock_station(best_station)
		_collect_events()


## Count distinct unlock/milestone-style progress events logged before `before_seconds`.
func distinct_progress_events(before_seconds: float) -> int:
	var seen: Dictionary = {}
	for entry in event_log:
		var t: float = float(entry[0])
		var id := str(entry[1])
		if t > before_seconds:
			continue
		for prefix in PROGRESS_EVENT_TYPES:
			if id.begins_with(prefix + ":"):
				seen[id] = true
	return seen.size()
