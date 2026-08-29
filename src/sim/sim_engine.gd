## SimEngine — pure, deterministic factory-line simulation (Theory of Constraints core loop).
## Fixed 0.1 s ticks, expected-value fluid flow (no RNG), no nodes/autoloads/EventBus.
## Construct with SimEngine.new_game(db); src/core/game.gd bridges drain_events() to the EventBus.
extends RefCounted

const BigNum = preload("res://src/sim/big_num.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const UpgradeMath = preload("res://src/sim/upgrade_math.gd")
const Effects = preload("res://src/sim/effects.gd")
const Milestones = preload("res://src/sim/milestones.gd")

const SAVE_VERSION := 1
const OEE_WINDOW_TICKS := 100	# ~10 s rolling window at 10 Hz
const MAX_QUEUED_EVENTS := 4096	# safety valve if nobody drains
const EVENT_BATCH_SECONDS := 1.0	# rate limit for part_sold / scrap_produced batches
const MIN_CYCLE_TIME := 0.01
const MIN_AVAILABILITY := 0.05
const EPS := 1e-9
const REL_EPS := 1e-6

# --- database (read-only after new_game) ---
var db: Dictionary = {}
var stations_def: Array = []	# sorted by "order"
var skills_def: Array = []
var milestones_def: Array = []
var achievements_def: Array = []
var balance: Dictionary = {}

# --- persistent economy / meta state ---
var money = null	# BigNum
var kp: float = 0.0
var cip: int = 0
var prestige_count: int = 0
var lifetime_parts = null	# BigNum, good parts sold, survives prestige
var money_earned = null	# BigNum, lifetime gross income
var scrap_total: float = 0.0
var time_played: float = 0.0
var purchased_skills: Dictionary = {}	# id -> true
var milestones_done: Dictionary = {}	# id -> true
var achievements_done: Dictionary = {}	# id -> true
var bottleneck_cleared_count: int = 0
var upgrade_purchase_count: int = 0	# lifetime levels bought
var zero_scrap_seconds: float = 0.0

# --- run state ---
var bottleneck: int = -1
var pps: float = 0.0	# instantaneous sold parts/sec (last tick)
var oee: float = 0.0

var _st: Array = []	# per-station runtime dicts
var _eff: Array = []	# per-station effective-stat cache
var _mods: Dictionary = {}	# aggregated skill effects (Effects.neutral shape)
var _global_mult: float = 1.0
var _sale_price = null	# BigNum per part sold at end of line
var _price_each_f: float = 0.0
var _buffer_cap: float = 100.0
var _ideal_pps: float = 0.0
var _k_unlocked: int = 0
var _unlocked_ids: Dictionary = {}
var _bn_start_pps: float = 0.0	# line steady pps when current bottleneck took over
var _started_total: float = 0.0	# raw parts pulled by station 0 (conservation)
var _sold_total: float = 0.0	# float mirror of lifetime sold (conservation)
var _wip_flushed: float = 0.0	# WIP scrapped by prestige resets (conservation)

var _events: Array = []
var _accept: Array = []	# per-tick acceptance bounds (preallocated, floats)
var _loading: bool = false
var _pending_milestones: Array = []
var _pending_achievements: Array = []
var _oee_window: Array = []
var _oee_idx: int = 0
var _oee_sum: float = 0.0
var _kp_last_emit: float = 0.0
var _autobuy_timer: float = 0.0
var _sold_batch: float = 0.0
var _sold_batch_rev = null	# BigNum
var _batch_timer: float = 0.0
var _snap: Dictionary = {}
var _snap_dirty: bool = true


# ------------------------------------------------------------------ construction

## Build a fresh engine from a db dictionary {stations, skills, milestones, achievements, balance}.
static func new_game(game_db: Dictionary):
	var engine = new()
	engine._setup_db(game_db)
	engine._reset_run_state(true)
	engine._rebuild_pending()
	engine._recompute()
	return engine


func _setup_db(game_db: Dictionary) -> void:
	db = game_db
	stations_def = []
	var raw_stations: Variant = game_db.get("stations", [])
	if typeof(raw_stations) == TYPE_ARRAY:
		for s in raw_stations:
			if typeof(s) == TYPE_DICTIONARY:
				stations_def.append(s)
	stations_def.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	skills_def = _as_array(game_db.get("skills", []))
	milestones_def = _as_array(game_db.get("milestones", []))
	achievements_def = _as_array(game_db.get("achievements", []))
	var bal: Variant = game_db.get("balance", {})
	balance = bal if typeof(bal) == TYPE_DICTIONARY else {}
	money = BigNum.zero()
	lifetime_parts = BigNum.zero()
	money_earned = BigNum.zero()
	_sale_price = BigNum.zero()
	_sold_batch_rev = BigNum.zero()
	_oee_window = []
	_oee_window.resize(OEE_WINDOW_TICKS)
	_oee_window.fill(0.0)


## Reset the per-run state (new game and prestige). Persistent meta is untouched unless
## `fresh` (new game) — then everything starts from zero.
func _reset_run_state(fresh: bool) -> void:
	if fresh:
		kp = 0.0
		cip = 0
		prestige_count = 0
		lifetime_parts = BigNum.zero()
		money_earned = BigNum.zero()
		scrap_total = 0.0
		time_played = 0.0
		purchased_skills = {}
		milestones_done = {}
		achievements_done = {}
		bottleneck_cleared_count = 0
		upgrade_purchase_count = 0
		_started_total = 0.0
		_sold_total = 0.0
		_wip_flushed = 0.0
	var mods: Dictionary = Effects.aggregate(skills_def, purchased_skills)
	var start_money: float = _bal_f("starting_money", 0.0) + float(mods["starting_money_add"])
	money = BigNum.from_float(start_money)
	zero_scrap_seconds = 0.0
	bottleneck = -1
	_bn_start_pps = 0.0
	pps = 0.0
	oee = 0.0
	_oee_window.fill(0.0)
	_oee_idx = 0
	_oee_sum = 0.0
	_autobuy_timer = 0.0
	_sold_batch = 0.0
	_sold_batch_rev = BigNum.zero()
	_batch_timer = 0.0
	_kp_last_emit = kp
	_accept = []
	_accept.resize(stations_def.size())
	_accept.fill(0.0)
	_st = []
	for def in stations_def:
		var levels: Dictionary = {}
		for uid in _upgrades_of(def):
			levels[uid] = 0
		_st.append({
			"unlocked": _unlock_cost_of(def).is_zero(),
			"levels": levels,
			"buffer": 0.0,
			"progress": 0.0,
			"status": SimTypes.STATUS_IDLE,
			"part_acc": 0.0,
			"scrap_acc": 0.0,
			"scrap_rate": 0.0,
		})
	_refresh_unlock_cache()
	_snap_dirty = true


func _rebuild_pending() -> void:
	_pending_milestones = []
	for def in milestones_def:
		if not milestones_done.has(str(def.get("id", ""))):
			_pending_milestones.append(def)
	_pending_achievements = []
	for def in achievements_def:
		if not achievements_done.has(str(def.get("id", ""))):
			_pending_achievements.append(def)


# ------------------------------------------------------------------ derived-state cache

## Recompute skill mods, per-station effective stats, price, ideal pps and the bottleneck.
## Call after anything that changes stats (purchase, unlock, skill, prestige, load).
func _recompute() -> void:
	_mods = Effects.aggregate(skills_def, purchased_skills)
	_global_mult = float(_mods["global_throughput_mult"]) * cip_multiplier()
	_buffer_cap = maxf(_bal_f("buffer_base_cap", 100.0) * float(_mods["buffer_cap_mult"]), 1.0)
	_price_each_f = _bal_f("price_per_part", 1.0) * float(_mods["price_mult"])
	if _value_add_pricing():
		# Value-add pricing (balance.value_add_pricing): every unlocked stage adds one
		# price unit per part — the ToC "throughput = money rate" reading. Makes line
		# extension a genuine revenue decision instead of a yield penalty.
		_price_each_f *= maxf(1.0, float(_k_unlocked))
	_sale_price = BigNum.from_float(_price_each_f)
	_eff = []
	for i in stations_def.size():
		_eff.append(_compute_station_eff(i, _st[i]["levels"]))
	_ideal_pps = INF
	for i in _k_unlocked:
		var e: Dictionary = _eff[i]
		var ideal: float = float(e["capacity"]) / float(e["cycle_time"]) * _global_mult
		_ideal_pps = minf(_ideal_pps, ideal)
	if _k_unlocked == 0:
		_ideal_pps = 0.0
	_update_bottleneck()
	_snap_dirty = true


## Effective stats for station index `i` given an upgrade-level dict. Order:
## base -> upgrade effects per level -> skill stat mods -> clamps -> derived rates.
func _compute_station_eff(i: int, levels: Dictionary) -> Dictionary:
	var def: Dictionary = stations_def[i]
	var base_v: Variant = def.get("base", {})
	var base: Dictionary = base_v if typeof(base_v) == TYPE_DICTIONARY else {}
	var stats := {
		"cycle_time": float(base.get("cycle_time", 1.0)),
		"uptime": float(base.get("uptime", 1.0)),
		"quality": float(base.get("quality", 1.0)),
		"capacity": float(base.get("capacity", 1.0)),
		"changeover_time": float(base.get("changeover_time", 0.0)),
		"operator_count": float(base.get("operator_count", 1.0)),
	}
	var upgrades: Dictionary = _upgrades_of(def)
	for uid in upgrades:
		var lvl: int = int(levels.get(uid, 0))
		if lvl <= 0:
			continue
		var u: Dictionary = upgrades[uid]
		var eff_v: Variant = u.get("effect", {})
		if typeof(eff_v) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = eff_v
		var stat := str(effect.get("stat", ""))
		if not stats.has(stat):
			continue
		var value: float = float(effect.get("value", 0.0))
		var cur: float = float(stats[stat])
		match str(effect.get("op", "")):
			"mul":
				stats[stat] = cur * pow(value, float(lvl))
			"add":
				stats[stat] = cur + value * float(lvl)
			"toward_one":
				stats[stat] = 1.0 - (1.0 - cur) * pow(1.0 - clampf(value, 0.0, 1.0), float(lvl))
	Effects.apply_station_mods(stats, str(def.get("id", "")), _mods["station_mods"])
	# Clamps.
	var period: float = maxf(_bal_f("changeover_period_seconds", 600.0), 1.0)
	stats["cycle_time"] = maxf(float(stats["cycle_time"]), MIN_CYCLE_TIME)
	stats["uptime"] = clampf(float(stats["uptime"]), 0.0, 1.0)
	stats["quality"] = clampf(float(stats["quality"]), 0.0, 1.0)
	stats["capacity"] = maxf(float(stats["capacity"]), 0.05)
	stats["changeover_time"] = clampf(float(stats["changeover_time"]), 0.0, period)
	stats["operator_count"] = maxf(float(stats["operator_count"]), 0.0)
	# Derived.
	var availability: float = clampf(
		float(stats["uptime"]) * (1.0 - float(stats["changeover_time"]) / period),
		MIN_AVAILABILITY, 1.0)
	stats["availability"] = availability
	var proc: float = float(stats["capacity"]) * availability / float(stats["cycle_time"]) * _global_mult
	stats["proc_rate"] = proc	# parts/sec pulled+processed (pre-quality)
	stats["throughput"] = proc * float(stats["quality"])	# contract §6 effective throughput
	return stats


func _refresh_unlock_cache() -> void:
	_k_unlocked = 0
	_unlocked_ids = {}
	for i in _st.size():
		if bool(_st[i]["unlocked"]):
			if i == _k_unlocked:
				_k_unlocked += 1
			_unlocked_ids[str(stations_def[i].get("id", ""))] = true
		# Non-prefix unlocks are defensive-normalized away in load_state; the cache
		# counts the contiguous prefix that forms the live line.


# ------------------------------------------------------------------ tick

## Advance the simulation one fixed step (dt = 0.1 s).
func tick(dt: float) -> void:
	if _k_unlocked <= 0 or dt <= 0.0:
		return
	dt = minf(dt, 1.0)
	time_played += dt
	_flow(dt)
	_update_oee(dt)
	_kp_passive(dt)
	_auto_buyer(dt)
	_check_triggers()
	_snap_dirty = true


## Fluid flow pass in two sweeps. Sweep 1 (downstream-first) bounds how much each station
## may process this tick given downstream buffer space freed by downstream consumption;
## sweep 2 (upstream-first) propagates actual flow with same-tick availability, so the
## line's throughput is never artificially capped at buffer_cap/dt parts per second.
func _flow(dt: float) -> void:
	var last: int = _k_unlocked - 1
	var sold_this: float = 0.0
	var processed_this: float = 0.0
	var scrap_this: float = 0.0
	var refund_frac: float = float(_mods["scrap_refund_frac"])
	var refund_money: float = 0.0
	var part_events_on: bool = pps <= _bal_sub_f("visual", "part_event_max_pps", 8.0)
	# Sweep 1: acceptance bound per station (space binds only where quality lands parts).
	for i in range(last, -1, -1):
		var eff: Dictionary = _eff[i]
		var want: float = float(eff["proc_rate"]) * dt
		if i == last:
			_accept[i] = want
			continue
		var q: float = float(eff["quality"])
		if q <= EPS:
			_accept[i] = want	# everything scraps; downstream space is irrelevant
			continue
		var space: float = _buffer_cap - float(_st[i + 1]["buffer"]) + _accept[i + 1]
		_accept[i] = clampf(space / q, 0.0, want)
	# Sweep 2: actual flow with same-tick pass-through.
	var inflow: float = 0.0	# good parts arriving from upstream this tick
	for i in range(0, last + 1):
		var st: Dictionary = _st[i]
		var eff: Dictionary = _eff[i]
		var q: float = float(eff["quality"])
		var want: float = float(eff["proc_rate"]) * dt
		if want <= EPS:
			_set_status(i, SimTypes.STATUS_IDLE)
			st["scrap_rate"] = 0.0
			if i > 0:
				st["buffer"] = float(st["buffer"]) + inflow	# park upstream's output as WIP
			inflow = 0.0
			continue
		var bound: float = float(_accept[i])
		var in_avail: float = INF
		if i > 0:
			in_avail = float(st["buffer"]) + inflow
		var k: float = maxf(minf(bound, in_avail), 0.0)
		# Status: RUNNING at full rate, else STARVED when input bound it, else BLOCKED.
		if k >= want * (1.0 - REL_EPS):
			_set_status(i, SimTypes.STATUS_RUNNING)
		elif i > 0 and in_avail < bound * (1.0 - REL_EPS):
			_set_status(i, SimTypes.STATUS_STARVED)
		else:
			_set_status(i, SimTypes.STATUS_BLOCKED)
		if i > 0:
			st["buffer"] = maxf(float(st["buffer"]) + inflow - k, 0.0)
		else:
			_started_total += k
		var good: float = k * q
		var scrap: float = k - good
		if i < last:
			inflow = good
		else:
			sold_this += good
		processed_this += k
		st["progress"] = fmod(float(st["progress"]) + dt / float(eff["cycle_time"]) * (k / want), 1.0)
		st["scrap_rate"] = scrap / dt
		if scrap > EPS:
			st["scrap_acc"] = float(st["scrap_acc"]) + scrap
			scrap_this += scrap
			scrap_total += scrap
			if refund_frac > 0.0:
				refund_money += scrap * _station_value_f(i) * refund_frac
		if part_events_on:
			st["part_acc"] = float(st["part_acc"]) + good
			while float(st["part_acc"]) >= 1.0:
				st["part_acc"] = float(st["part_acc"]) - 1.0
				_queue({"t": "part_completed", "station": i})
		else:
			st["part_acc"] = 0.0
	pps = sold_this / dt
	if sold_this > 0.0:
		var revenue = _sale_price.mul_f(sold_this)
		money = money.add(revenue)
		money_earned = money_earned.add(revenue)
		lifetime_parts = lifetime_parts.add(BigNum.from_float(sold_this))
		_sold_total += sold_this
		_sold_batch += sold_this
		_sold_batch_rev = _sold_batch_rev.add(revenue)
	if refund_money > 0.0:
		var refund = BigNum.from_float(refund_money)
		money = money.add(refund)
		money_earned = money_earned.add(refund)
	# Zero-scrap streak: must actually be producing; any scrap resets it.
	if processed_this > EPS:
		if scrap_this <= processed_this * EPS:
			zero_scrap_seconds += dt
		else:
			zero_scrap_seconds = 0.0
	# Batched notification events (~1/s).
	_batch_timer += dt
	if _batch_timer >= EVENT_BATCH_SECONDS:
		_batch_timer = 0.0
		if _sold_batch > EPS:
			_queue({"t": "part_sold", "count": _sold_batch, "revenue": _sold_batch_rev})
			_sold_batch = 0.0
			_sold_batch_rev = BigNum.zero()
		for i in _k_unlocked:
			var sti: Dictionary = _st[i]
			if float(sti["scrap_acc"]) > 0.005:
				_queue({"t": "scrap_produced", "station": i, "amount": float(sti["scrap_acc"])})
				sti["scrap_acc"] = 0.0


func _set_status(i: int, status: int) -> void:
	var st: Dictionary = _st[i]
	if int(st["status"]) == status:
		return
	st["status"] = status
	_queue({"t": "station_status_changed", "station": i, "status": status})


## Bottleneck = unlocked station with the lowest effective throughput (ties -> lowest index).
## bottleneck_cleared fires when it moves off a station AND line pps strictly improved
## since that station became the bottleneck.
func _update_bottleneck() -> void:
	var best: int = -1
	var best_tp: float = INF
	for i in _k_unlocked:
		var tp: float = float(_eff[i]["throughput"])
		if tp < best_tp - EPS:
			best_tp = tp
			best = i
	if best == bottleneck:
		return
	var old: int = bottleneck
	var line_now: float = estimate_steady_pps()
	if old != -1 and not _loading and line_now > _bn_start_pps * (1.0 + REL_EPS) + EPS:
		bottleneck_cleared_count += 1
		_queue({"t": "bottleneck_cleared", "station": old})
	bottleneck = best
	_bn_start_pps = line_now
	_queue({"t": "bottleneck_changed", "new_index": best, "old_index": old})


func _update_oee(dt: float) -> void:
	var sold_this: float = pps * dt
	_oee_sum += sold_this - float(_oee_window[_oee_idx])
	_oee_window[_oee_idx] = sold_this
	_oee_idx = (_oee_idx + 1) % OEE_WINDOW_TICKS
	var actual: float = maxf(_oee_sum, 0.0) / (float(OEE_WINDOW_TICKS) * dt)
	oee = clampf(actual / _ideal_pps, 0.0, 1.0) if _ideal_pps > EPS else 0.0


func _kp_passive(dt: float) -> void:
	var per_min: float = float(_mods["kp_passive_per_min"])
	if per_min <= 0.0:
		return
	kp += per_min / 60.0 * dt
	if absf(kp - _kp_last_emit) >= 1.0:
		_kp_last_emit = kp
		_queue({"t": "kaizen_points_changed", "total": kp})


## CI manager (auto_buyer skill): greedily buys the best delta-throughput/cost single
## upgrade level at its configured interval.
func _auto_buyer(dt: float) -> void:
	var interval: float = float(_mods["auto_buyer_interval"])
	if interval <= 0.0:
		return
	_autobuy_timer += dt
	var guard: int = 0
	while _autobuy_timer >= interval and guard < 16:
		_autobuy_timer -= interval
		guard += 1
		_auto_buy_once()


func _auto_buy_once() -> void:
	var best_station: int = -1
	var best_uid: String = ""
	var best_score = null	# BigNum delta/cost
	for i in _k_unlocked:
		var def: Dictionary = stations_def[i]
		var upgrades: Dictionary = _upgrades_of(def)
		var levels: Dictionary = _st[i]["levels"]
		for uid in upgrades:
			var u: Dictionary = upgrades[uid]
			var lvl: int = int(levels.get(uid, 0))
			var max_level: int = int(u.get("max_level", 0))
			if max_level > 0 and lvl >= max_level:
				continue
			var cost = UpgradeMath.level_cost(
				_num_f(u.get("base_cost", 0.0), 0.0), float(u.get("growth", 1.0)), lvl,
				float(_mods["upgrade_cost_mult"]))
			if money.lt(cost):
				continue
			var delta: float = estimate_upgrade_delta_pps(i, uid)
			if delta <= EPS:
				continue
			var score = BigNum.from_float(delta).div(cost)
			if best_score == null or score.gt(best_score):
				best_score = score
				best_station = i
				best_uid = uid
	if best_station >= 0:
		buy_upgrade(best_station, best_uid, 1)


func _check_triggers() -> void:
	if _pending_milestones.is_empty() and _pending_achievements.is_empty():
		return
	var facts := {
		"lifetime_parts": lifetime_parts,
		"money_earned": money_earned,
		"pps": pps,
		"oee": oee,
		"bottleneck_cleared_count": bottleneck_cleared_count,
		"unlocked_ids": _unlocked_ids,
		"upgrade_count": upgrade_purchase_count,
		"skill_count": purchased_skills.size(),
		"prestige_count": prestige_count,
		"zero_scrap_seconds": zero_scrap_seconds,
	}
	if not _pending_milestones.is_empty():
		var hit: Array = Milestones.evaluate(_pending_milestones, facts)
		for def in hit:
			var id := str(def.get("id", ""))
			var gained: int = int(def.get("kp", 0))
			milestones_done[id] = true
			_pending_milestones.erase(def)
			kp += float(gained)
			_kp_last_emit = kp
			_queue({"t": "milestone_reached", "id": id, "kp_gained": gained})
			_queue({"t": "kaizen_points_changed", "total": kp})
	if not _pending_achievements.is_empty():
		var hit_a: Array = Milestones.evaluate(_pending_achievements, facts)
		for def in hit_a:
			var id := str(def.get("id", ""))
			achievements_done[id] = true
			_pending_achievements.erase(def)
			_queue({"t": "achievement_unlocked", "id": id})


# ------------------------------------------------------------------ commands

## Buy `multiplier` levels (1/10/100 or SimTypes.BUY_MAX) of one upgrade. All-or-nothing
## for fixed counts (clamped to max_level headroom); BUY_MAX buys the most affordable.
func buy_upgrade(station: int, upgrade_id: String, multiplier: int = 1) -> bool:
	if station < 0 or station >= _k_unlocked:
		return false
	var def: Dictionary = stations_def[station]
	var upgrades: Dictionary = _upgrades_of(def)
	if not upgrades.has(upgrade_id):
		return false
	var u: Dictionary = upgrades[upgrade_id]
	var levels: Dictionary = _st[station]["levels"]
	var lvl: int = int(levels.get(upgrade_id, 0))
	var headroom: int = _headroom(u, lvl)
	if headroom <= 0:
		return false
	var base_cost: float = _num_f(u.get("base_cost", 0.0), 0.0)
	var growth: float = float(u.get("growth", 1.0))
	var cost_mult: float = float(_mods["upgrade_cost_mult"])
	var count: int = 0
	if multiplier == SimTypes.BUY_MAX:
		count = mini(UpgradeMath.max_affordable(base_cost, growth, lvl, money, cost_mult), headroom)
		if count <= 0:
			return false
	else:
		count = mini(maxi(multiplier, 1), headroom)
	var cost = UpgradeMath.bulk_cost(base_cost, growth, lvl, count, cost_mult)
	if money.lt(cost):
		return false
	money = money.sub(cost)
	levels[upgrade_id] = lvl + count
	upgrade_purchase_count += count
	_queue({"t": "money_spent", "amount": cost, "context": "upgrade"})
	_queue({"t": "station_upgraded", "station": station, "upgrade_id": upgrade_id,
			"levels": count, "new_level": lvl + count})
	_recompute()
	return true


## Unlock the next locked station in line order (out-of-order unlocks are rejected).
func unlock_station(station: int) -> bool:
	if station != next_locked_index():
		return false
	var def: Dictionary = stations_def[station]
	var cost = _unlock_cost_of(def)
	if money.lt(cost):
		return false
	money = money.sub(cost)
	_st[station]["unlocked"] = true
	_refresh_unlock_cache()
	_queue({"t": "money_spent", "amount": cost, "context": "unlock"})
	_queue({"t": "station_unlocked", "station": station})
	_recompute()
	return true


## Spend KP on a skill node (prereqs must be purchased).
func buy_skill(node_id: String) -> bool:
	var def: Dictionary = _skill_def(node_id)
	if def.is_empty() or purchased_skills.has(node_id):
		return false
	if not _prereqs_met(def):
		return false
	var cost: int = int(def.get("cost", 0))
	if kp < float(cost):
		return false
	kp -= float(cost)
	_kp_last_emit = kp
	purchased_skills[node_id] = true
	_queue({"t": "skill_purchased", "node_id": node_id})
	_queue({"t": "kaizen_points_changed", "total": kp})
	_recompute()
	return true


## Kaizen Event (prestige): convert lifetime parts into CIP, reset the run, keep the meta.
func do_prestige() -> bool:
	var view := get_prestige_view()
	if not bool(view["can_prestige"]):
		return false
	var gained: int = int(view["cip_gain"])
	cip += gained
	prestige_count += 1
	for i in _st.size():
		_wip_flushed += float(_st[i]["buffer"])	# selling the factory scraps in-line WIP
	_reset_run_state(false)
	_recompute()
	_queue({"t": "prestige_performed", "cip_gained": gained, "new_multiplier": cip_multiplier()})
	_check_triggers()	# prestige_count milestones fire immediately
	_snap_dirty = true
	return true


# ------------------------------------------------------------------ views

func get_station_view(station: int) -> Dictionary:
	if station < 0 or station >= stations_def.size():
		return {}
	var def: Dictionary = stations_def[station]
	var st: Dictionary = _st[station]
	var eff: Dictionary = _eff[station]
	var unlocked: bool = bool(st["unlocked"])
	var name_key := str(def.get("name_key", def.get("id", "")))
	return {
		"index": station,
		"id": str(def.get("id", "")),
		"name": name_key,	# Game bridge localizes via L.t(); sim stays autoload-free
		"name_key": name_key,
		"unlocked": unlocked,
		"status": int(st["status"]),
		"is_bottleneck": unlocked and station == bottleneck,
		"stats": {
			"cycle_time": float(eff["cycle_time"]),
			"uptime": float(eff["uptime"]),
			"quality": float(eff["quality"]),
			"capacity": maxi(int(roundf(float(eff["capacity"]))), 1),
			"changeover_time": float(eff["changeover_time"]),
			"operator_count": int(roundf(float(eff["operator_count"]))),
		},
		"throughput": float(eff["throughput"]),
		"progress": float(st["progress"]),
		"buffer_in": float(st["buffer"]) if station > 0 else 0.0,
		"buffer_in_cap": _buffer_cap if station > 0 else 0.0,
		"scrap_rate": float(st["scrap_rate"]),
		"upgrade_levels": (st["levels"] as Dictionary).duplicate(),
		"unlock_cost": _unlock_cost_of(def),
	}


## Upgrade purchase preview honoring the buy multiplier (BUY_MAX = most affordable, min 1 priced).
func get_upgrade_view(station: int, upgrade_id: String, multiplier: int = 1) -> Dictionary:
	var out := {"cost": BigNum.zero(), "count": 0, "affordable": false, "maxed": false,
			"helps_bottleneck": false}
	if station < 0 or station >= stations_def.size():
		return out
	var upgrades: Dictionary = _upgrades_of(stations_def[station])
	if not upgrades.has(upgrade_id):
		return out
	var u: Dictionary = upgrades[upgrade_id]
	var lvl: int = int((_st[station]["levels"] as Dictionary).get(upgrade_id, 0))
	var headroom: int = _headroom(u, lvl)
	if headroom <= 0:
		out["maxed"] = true
		return out
	var base_cost: float = _num_f(u.get("base_cost", 0.0), 0.0)
	var growth: float = float(u.get("growth", 1.0))
	var cost_mult: float = float(_mods["upgrade_cost_mult"])
	var count: int = 0
	if multiplier == SimTypes.BUY_MAX:
		count = clampi(UpgradeMath.max_affordable(base_cost, growth, lvl, money, cost_mult), 1, headroom)
	else:
		count = mini(maxi(multiplier, 1), headroom)
	var cost = UpgradeMath.bulk_cost(base_cost, growth, lvl, count, cost_mult)
	out["cost"] = cost
	out["count"] = count
	out["affordable"] = money.ge(cost)
	out["helps_bottleneck"] = station == bottleneck and estimate_upgrade_delta_pps(station, upgrade_id) > EPS
	return out


func get_prestige_view() -> Dictionary:
	var divisor: float = maxf(_bal_sub_f("prestige", "divisor", 10000.0), 1.0)
	var exponent: float = _bal_sub_f("prestige", "exponent", 0.5)
	var min_parts = Milestones.to_bignum(_bal_sub("prestige", "min_lifetime_parts", 50000.0))
	var total: int = _total_cip_for(lifetime_parts, divisor, exponent)
	var gain: int = maxi(total - cip, 0)
	var per_cip: float = _bal_sub_f("prestige", "multiplier_per_cip", 0.1)
	return {
		"cip_current": cip,
		"cip_gain": gain,
		"multiplier_now": cip_multiplier(),
		"multiplier_after": 1.0 + float(cip + gain) * per_cip,
		"lifetime_parts": lifetime_parts,
		"min_parts": min_parts,
		"can_prestige": lifetime_parts.ge(min_parts) and gain >= 1,
	}


func get_skill_state(node_id: String) -> Dictionary:
	var def: Dictionary = _skill_def(node_id)
	if def.is_empty():
		return {"purchased": false, "available": false, "affordable": false, "cost": 0}
	var cost: int = int(def.get("cost", 0))
	var purchased: bool = purchased_skills.has(node_id)
	return {
		"purchased": purchased,
		"available": (not purchased) and _prereqs_met(def),
		"affordable": kp >= float(cost),
		"cost": cost,
	}


## Snapshot for EventBus.sim_stats — contract shape plus additive extras (rps, features).
func get_stats_snapshot() -> Dictionary:
	if not _snap_dirty and not _snap.is_empty():
		return _snap
	var station_views: Array[Dictionary] = []
	for i in stations_def.size():
		station_views.append(get_station_view(i))
	_snap = {
		"money": money,
		"pps": pps,
		"oee": oee,
		"bottleneck": bottleneck,
		"kp": kp,
		"cip": cip,
		"cip_mult": cip_multiplier(),
		"lifetime_parts": lifetime_parts,
		"scrap_total": scrap_total,
		"time_played": time_played,
		"prestige_count": prestige_count,
		"stations": station_views,
		"rps": _sale_price.mul_f(pps),
		"features": (_mods["features"] as Array).duplicate(),
	}
	_snap_dirty = false
	return _snap


# ------------------------------------------------------------------ offline

## Closed-form offline progression: steady-state pps x credited seconds, honoring the
## offline cap (base + skill hours) and rate multipliers. O(stations) — far under 50 ms.
func offline_progress(seconds: float) -> Dictionary:
	var report := {
		"seconds": 0.0, "capped": false,
		"parts": BigNum.zero(), "money": BigNum.zero(),
		"kp": 0.0, "raw_seconds": seconds,
	}
	var min_seconds: float = _bal_sub_f("offline", "min_seconds", 0.0)
	if seconds < min_seconds or seconds <= 0.0 or _k_unlocked <= 0:
		return report
	var cap_hours: float = _bal_sub_f("offline", "cap_hours_base", 8.0) + float(_mods["offline_cap_add_hours"])
	var cap_s: float = maxf(cap_hours, 0.0) * 3600.0
	var credited: float = minf(seconds, cap_s)
	var capped: bool = seconds > cap_s
	var rate: float = _bal_sub_f("offline", "rate", 1.0) * float(_mods["offline_rate_mult"])
	var sold: float = estimate_steady_pps() * credited * rate
	var refund_frac: float = float(_mods["scrap_refund_frac"])
	if sold > 0.0:
		# Every sold part passed every station: started = sold / prod(quality).
		var yield_all: float = 1.0
		for i in _k_unlocked:
			yield_all *= maxf(float(_eff[i]["quality"]), EPS)
		var started: float = sold / yield_all
		var revenue = _sale_price.mul_f(sold)
		# Per-station scrap (and optional refunds) along the steady flow.
		var flow: float = started
		var refund_money: float = 0.0
		var scrap_sum: float = 0.0
		for i in _k_unlocked:
			var q: float = float(_eff[i]["quality"])
			var scrap_i: float = flow * (1.0 - q)
			scrap_sum += scrap_i
			if refund_frac > 0.0 and scrap_i > 0.0:
				refund_money += scrap_i * _station_value_f(i) * refund_frac
			flow *= q
		money = money.add(revenue)
		money_earned = money_earned.add(revenue)
		if refund_money > 0.0:
			var refund = BigNum.from_float(refund_money)
			money = money.add(refund)
			money_earned = money_earned.add(refund)
		lifetime_parts = lifetime_parts.add(BigNum.from_float(sold))
		_sold_total += sold
		_started_total += started
		scrap_total += scrap_sum
		report["money"] = revenue
		report["parts"] = BigNum.from_float(sold)
	var kp_gain: float = float(_mods["kp_passive_per_min"]) / 60.0 * credited * rate
	if kp_gain > 0.0:
		kp += kp_gain
		_kp_last_emit = kp
		_queue({"t": "kaizen_points_changed", "total": kp})
	report["seconds"] = credited
	report["capped"] = capped
	report["kp"] = kp_gain
	_check_triggers()
	_snap_dirty = true
	return report


# ------------------------------------------------------------------ estimators (public: used by auto-buyer, autoplayer, UI hints)

## Steady-state sold parts/sec of the current line: min over stations of
## proc_rate x (product of quality from that station to the end).
func estimate_steady_pps() -> float:
	return _steady_pps_with(-1, {})


## Change in steady sold pps from buying ONE level of an upgrade.
func estimate_upgrade_delta_pps(station: int, upgrade_id: String) -> float:
	if station < 0 or station >= _k_unlocked:
		return 0.0
	var levels: Dictionary = (_st[station]["levels"] as Dictionary).duplicate()
	if not levels.has(upgrade_id):
		return 0.0
	levels[upgrade_id] = int(levels[upgrade_id]) + 1
	var eff_after: Dictionary = _compute_station_eff(station, levels)
	return _steady_pps_with(station, eff_after) - estimate_steady_pps()


## Change in steady revenue/sec (float, price units) from buying ONE level of an upgrade.
func estimate_upgrade_delta_rps(station: int, upgrade_id: String) -> float:
	return estimate_upgrade_delta_pps(station, upgrade_id) * _price_each_f


## Change in steady revenue/sec (float, price units) from unlocking the next station.
func estimate_unlock_delta_rps(station: int) -> float:
	if station != next_locked_index():
		return 0.0
	var eff_new: Dictionary = _compute_station_eff(station, _st[station]["levels"])
	var cur_rps: float = estimate_steady_pps() * _price_each_f
	# Cascade including the would-be station appended at the end of the line.
	var best: float = float(eff_new["proc_rate"]) * float(eff_new["quality"])
	var suffix_q: float = float(eff_new["quality"])
	for i in range(_k_unlocked - 1, -1, -1):
		var eff: Dictionary = _eff[i]
		suffix_q *= float(eff["quality"])
		best = minf(best, float(eff["proc_rate"]) * suffix_q)
	var price_after: float = _price_each_f
	if _value_add_pricing() and _k_unlocked > 0:
		# The unlocked line will sell at the (k+1)-station price.
		price_after = _price_each_f / float(_k_unlocked) * float(_k_unlocked + 1)
	return best * price_after - cur_rps


func _steady_pps_with(override_index: int, override_eff: Dictionary) -> float:
	if _k_unlocked <= 0:
		return 0.0
	var best: float = INF
	var suffix_q: float = 1.0
	for i in range(_k_unlocked - 1, -1, -1):
		var eff: Dictionary = _eff[i]
		if i == override_index:
			eff = override_eff
		suffix_q *= float(eff["quality"])
		best = minf(best, float(eff["proc_rate"]) * suffix_q)
	return best


## Index of the next station that can be unlocked, or -1 when the line is complete.
func next_locked_index() -> int:
	if _k_unlocked < stations_def.size():
		return _k_unlocked
	return -1


func cip_multiplier() -> float:
	return 1.0 + float(cip) * _bal_sub_f("prestige", "multiplier_per_cip", 0.1)


func get_feature_unlocked(feature: String) -> bool:
	return (_mods["features"] as Array).has(feature)


## Conservation counters for tests: parts started = sold + scrap + wip + flushed
## (flushed = WIP discarded by prestige resets).
func debug_totals() -> Dictionary:
	var wip: float = 0.0
	for i in _st.size():
		wip += float(_st[i]["buffer"])
	return {"started": _started_total, "sold": _sold_total, "scrap": scrap_total,
			"wip": wip, "flushed": _wip_flushed}


# ------------------------------------------------------------------ events

## Drain and clear the queued transition events ({"t": <EventBus signal name>, ...}).
func drain_events() -> Array:
	var out: Array = _events
	_events = []
	return out


func _queue(ev: Dictionary) -> void:
	if _loading:
		return
	if _events.size() >= MAX_QUEUED_EVENTS:
		_events.pop_front()
	_events.append(ev)


# ------------------------------------------------------------------ serialization

## Full save-state dictionary; BigNums serialize as {"m","e"}.
func serialize() -> Dictionary:
	var stations_out: Array = []
	for i in stations_def.size():
		var st: Dictionary = _st[i]
		stations_out.append({
			"id": str(stations_def[i].get("id", "")),
			"unlocked": bool(st["unlocked"]),
			"levels": (st["levels"] as Dictionary).duplicate(),
			"buffer": float(st["buffer"]),
		})
	return {
		"version": SAVE_VERSION,
		"money": money.to_dict(),
		"kp": kp,
		"cip": cip,
		"prestige_count": prestige_count,
		"lifetime_parts": lifetime_parts.to_dict(),
		"money_earned": money_earned.to_dict(),
		"scrap_total": scrap_total,
		"time_played": time_played,
		"bottleneck_cleared_count": bottleneck_cleared_count,
		"upgrade_purchase_count": upgrade_purchase_count,
		"zero_scrap_seconds": zero_scrap_seconds,
		"started_total": _started_total,
		"sold_total": _sold_total,
		"wip_flushed": _wip_flushed,
		"bn_start_pps": _bn_start_pps,
		"purchased_skills": purchased_skills.keys(),
		"milestones_done": milestones_done.keys(),
		"achievements_done": achievements_done.keys(),
		"stations": stations_out,
	}


## Restore a serialized state (same db). Unknown ids are dropped, missing keys defaulted,
## non-prefix unlocks normalized. Returns false only for fundamentally unusable input.
func load_state(state: Dictionary) -> bool:
	if typeof(state) != TYPE_DICTIONARY or state.is_empty():
		return false
	var version: int = int(state.get("version", SAVE_VERSION))
	if version > SAVE_VERSION or version < 1:
		return false
	_loading = true
	_reset_run_state(true)
	money = BigNum.from_dict(state.get("money", {}))
	kp = float(state.get("kp", 0.0))
	cip = maxi(int(state.get("cip", 0)), 0)
	prestige_count = maxi(int(state.get("prestige_count", 0)), 0)
	lifetime_parts = BigNum.from_dict(state.get("lifetime_parts", {}))
	money_earned = BigNum.from_dict(state.get("money_earned", {}))
	scrap_total = float(state.get("scrap_total", 0.0))
	time_played = float(state.get("time_played", 0.0))
	bottleneck_cleared_count = maxi(int(state.get("bottleneck_cleared_count", 0)), 0)
	upgrade_purchase_count = maxi(int(state.get("upgrade_purchase_count", 0)), 0)
	zero_scrap_seconds = float(state.get("zero_scrap_seconds", 0.0))
	_started_total = float(state.get("started_total", 0.0))
	_sold_total = float(state.get("sold_total", 0.0))
	_wip_flushed = float(state.get("wip_flushed", 0.0))
	_bn_start_pps = float(state.get("bn_start_pps", 0.0))
	_kp_last_emit = kp
	purchased_skills = {}
	for id in _as_array(state.get("purchased_skills", [])):
		if not _skill_def(str(id)).is_empty():
			purchased_skills[str(id)] = true
	milestones_done = {}
	for id in _as_array(state.get("milestones_done", [])):
		milestones_done[str(id)] = true
	achievements_done = {}
	for id in _as_array(state.get("achievements_done", [])):
		achievements_done[str(id)] = true
	# Stations by id; unlocked flags must form a prefix (line topology is linear).
	var by_id: Dictionary = {}
	for entry in _as_array(state.get("stations", [])):
		if typeof(entry) == TYPE_DICTIONARY:
			by_id[str(entry.get("id", ""))] = entry
	var prefix_ok: bool = true
	for i in stations_def.size():
		var def: Dictionary = stations_def[i]
		var st: Dictionary = _st[i]
		var entry_v: Variant = by_id.get(str(def.get("id", "")), {})
		var entry: Dictionary = entry_v if typeof(entry_v) == TYPE_DICTIONARY else {}
		var starts_unlocked: bool = _unlock_cost_of(def).is_zero()
		var want_unlocked: bool = bool(entry.get("unlocked", starts_unlocked)) or starts_unlocked
		st["unlocked"] = want_unlocked and prefix_ok
		if not bool(st["unlocked"]):
			prefix_ok = false
		st["buffer"] = maxf(float(entry.get("buffer", 0.0)), 0.0)
		var levels_v: Variant = entry.get("levels", {})
		var levels_in: Dictionary = levels_v if typeof(levels_v) == TYPE_DICTIONARY else {}
		var levels: Dictionary = st["levels"]
		var upgrades: Dictionary = _upgrades_of(def)
		for uid in levels:
			var lvl: int = maxi(int(levels_in.get(uid, 0)), 0)
			var u: Dictionary = upgrades[uid]
			var max_level: int = int(u.get("max_level", 0))
			if max_level > 0:
				lvl = mini(lvl, max_level)
			levels[uid] = lvl
	_refresh_unlock_cache()
	# Clamp restored buffers to the (skill-modified) cap after effects are known.
	_rebuild_pending()
	_recompute()
	for i in _st.size():
		_st[i]["buffer"] = minf(float(_st[i]["buffer"]), _buffer_cap)
	_loading = false
	_events = []
	_snap_dirty = true
	return true


# ------------------------------------------------------------------ prestige math

func _total_cip_for(parts, divisor: float, exponent: float) -> int:
	var v = parts.div(BigNum.from_float(divisor))
	if v.is_zero() or v.m < 0.0:
		return 0
	var log10_v: float = log(v.m) / 2.302585092994046 + float(v.e)
	if log10_v < 0.0:
		return 0
	var t: float = log10_v * exponent
	if t >= 18.0:
		return int(4e18)	# saturate far beyond any real playthrough
	if v.e < 300:
		return int(floor(pow(v.to_float(), exponent) + 1e-9))
	return int(floor(pow(10.0, t) + 1e-9))


# ------------------------------------------------------------------ small utils

func _station_value_f(_i: int) -> float:
	# Value recovered per scrapped part (flat sale price; see INTEGRATION_NOTES on pricing).
	return _price_each_f


func _headroom(u: Dictionary, lvl: int) -> int:
	var max_level: int = int(u.get("max_level", 0))
	if max_level <= 0:
		return UpgradeMath.MAX_BULK_COUNT
	return maxi(max_level - lvl, 0)


func _upgrades_of(def: Dictionary) -> Dictionary:
	var u: Variant = def.get("upgrades", {})
	return u if typeof(u) == TYPE_DICTIONARY else {}


func _unlock_cost_of(def: Dictionary):
	return Milestones.to_bignum(def.get("unlock_cost", 0))


func _skill_def(node_id: String) -> Dictionary:
	for def in skills_def:
		if typeof(def) == TYPE_DICTIONARY and str(def.get("id", "")) == node_id:
			return def
	return {}


func _prereqs_met(def: Dictionary) -> bool:
	for pre in _as_array(def.get("prereqs", [])):
		if not purchased_skills.has(str(pre)):
			return false
	return true


func _as_array(v: Variant) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


## Money-like number from data: plain numbers or {"m","e"} BigNum dicts (the loader
## normalizes costs to the dict form). Saturates instead of overflowing.
func _num_f(v: Variant, default_value: float) -> float:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_DICTIONARY:
		var f: float = BigNum.from_dict(v).to_float()
		if is_inf(f):
			return 1.7e308
		return f
	return default_value


func _bal_f(key: String, default_value: float) -> float:
	return float(balance.get(key, default_value))


func _value_add_pricing() -> bool:
	return bool(balance.get("value_add_pricing", false))


func _bal_sub(sub: String, key: String, default_value: Variant) -> Variant:
	var d: Variant = balance.get(sub, {})
	if typeof(d) != TYPE_DICTIONARY:
		return default_value
	return d.get(key, default_value)


func _bal_sub_f(sub: String, key: String, default_value: float) -> float:
	return float(_bal_sub(sub, key, default_value))
