## Tests for the SimEngine production line: throughput formula, flow conservation,
## bottleneck detection/clearing, STARVED/BLOCKED semantics, buffer caps, selling.
extends "res://tests/test_framework.gd"

const Autoplayer = preload("res://tests/autoplayer.gd")
const SimEngineScript = preload("res://src/sim/sim_engine.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const BigNum = preload("res://src/sim/big_num.gd")


func _engine(db: Dictionary = {}):
	if db.is_empty():
		db = Autoplayer.fixture_db()
	return SimEngineScript.new_game(db)


func _run(engine, seconds: float) -> void:
	var ticks: int = int(roundf(seconds / SimTypes.TICK_DT))
	for _i in ticks:
		engine.tick(SimTypes.TICK_DT)


func _events_of(events: Array, t: String) -> Array:
	var out: Array = []
	for ev in events:
		if str(ev.get("t", "")) == t:
			out.append(ev)
	return out


func test_initial_state() -> void:
	var e = _engine()
	assert_near(e.money.to_float(), 100.0, 1e-9, "starting money from balance")
	var snap: Dictionary = e.get_stats_snapshot()
	assert_eq(snap["bottleneck"], 1, "beta (0.4 pps) is the initial bottleneck")
	assert_eq((snap["stations"] as Array).size(), 4, "all stations in snapshot, locked included")
	var delta_view: Dictionary = e.get_station_view(3)
	assert_false(bool(delta_view["unlocked"]))
	assert_near(delta_view["unlock_cost"].to_float(), 50.0, 1e-9)
	assert_eq(int(delta_view["status"]), SimTypes.STATUS_IDLE)
	for key in ["money", "pps", "oee", "bottleneck", "kp", "cip", "cip_mult",
			"lifetime_parts", "scrap_total", "time_played", "prestige_count", "stations"]:
		assert_true(snap.has(key), "snapshot key %s" % key)
	var sv: Dictionary = snap["stations"][0]
	for key in ["index", "id", "name", "unlocked", "status", "is_bottleneck", "stats",
			"throughput", "progress", "buffer_in", "buffer_in_cap", "scrap_rate",
			"upgrade_levels", "unlock_cost"]:
		assert_true(sv.has(key), "station view key %s" % key)
	var events: Array = e.drain_events()
	var bn: Array = _events_of(events, "bottleneck_changed")
	assert_eq(bn.size(), 1, "initial bottleneck_changed queued")
	assert_eq(int(bn[0]["new_index"]), 1)
	assert_eq(int(bn[0]["old_index"]), -1, "old index -1 on first detection")


func test_throughput_formula() -> void:
	var e = _engine()
	assert_near(float(e.get_station_view(0)["throughput"]), 1.0, 1e-9, "alpha 1*1*1/1")
	assert_near(float(e.get_station_view(1)["throughput"]), 0.4, 1e-9, "beta 1*1*0.8/2")
	# Changeover derates availability: uptime * (1 - changeover/period).
	var db: Dictionary = Autoplayer.fixture_db()
	db["stations"][0]["base"]["changeover_time"] = 60.0
	db["stations"][0]["base"]["uptime"] = 0.5
	var e2 = _engine(db)
	assert_near(float(e2.get_station_view(0)["throughput"]), 0.5 * (1.0 - 60.0 / 600.0), 1e-9)
	# Availability clamps at 0.05 even with absurd changeover.
	db = Autoplayer.fixture_db()
	db["stations"][0]["base"]["changeover_time"] = 600.0
	var e3 = _engine(db)
	assert_near(float(e3.get_station_view(0)["throughput"]), 0.05, 1e-9, "availability floor")


func test_conservation() -> void:
	var e = _engine()
	_run(e, 30.0)
	var t: Dictionary = e.debug_totals()
	var balance_sum: float = float(t["sold"]) + float(t["scrap"]) + float(t["wip"])
	assert_true(float(t["started"]) > 1.0, "line actually ran")
	assert_near(float(t["started"]), balance_sum, 1e-6 * float(t["started"]) + 1e-9,
			"parts started = sold + scrap + WIP")
	assert_near(e.lifetime_parts.to_float(), float(t["sold"]), 1e-6, "lifetime tracks sold")
	# Still conserved after upgrades change rates mid-run.
	e.buy_upgrade(1, "speed", 1)
	_run(e, 30.0)
	t = e.debug_totals()
	balance_sum = float(t["sold"]) + float(t["scrap"]) + float(t["wip"])
	assert_near(float(t["started"]), balance_sum, 1e-6 * float(t["started"]) + 1e-9,
			"conservation holds after upgrades")


func test_steady_state_pps() -> void:
	var e = _engine()
	# Steady sold = min over stations of proc_rate * suffix quality = beta: 0.5 * 0.8 = 0.4.
	assert_near(e.estimate_steady_pps(), 0.4, 1e-9)
	_run(e, 120.0)
	assert_near(e.pps, 0.4, 0.01, "instantaneous pps converges to steady value")
	var snap: Dictionary = e.get_stats_snapshot()
	assert_near(float(snap["pps"]), 0.4, 0.01)
	assert_true(float(snap["oee"]) > 0.5, "OEE window filled: 0.4 actual / 0.5 ideal")
	assert_true(float(snap["oee"]) <= 1.0)


func test_bottleneck_cleared_on_improvement() -> void:
	var e = _engine()
	e.money = BigNum.from_float(1e6)
	_run(e, 10.0)
	e.drain_events()
	# 10 speed levels on beta: cycle 2*0.9^10 -> throughput 1.148 > alpha 1.0.
	assert_true(e.buy_upgrade(1, "speed", 10))
	var events: Array = e.drain_events()
	var cleared: Array = _events_of(events, "bottleneck_cleared")
	assert_eq(cleared.size(), 1, "bottleneck_cleared fired")
	assert_eq(int(cleared[0]["station"]), 1, "cleared station was beta")
	var changed: Array = _events_of(events, "bottleneck_changed")
	assert_eq(changed.size(), 1)
	assert_eq(int(changed[0]["new_index"]), 0, "tie between alpha/gamma -> lowest index")
	assert_eq(int(changed[0]["old_index"]), 1)
	assert_eq(e.bottleneck_cleared_count, 1)
	assert_true(bool(e.get_station_view(0)["is_bottleneck"]))
	assert_false(bool(e.get_station_view(1)["is_bottleneck"]))


func test_bottleneck_move_without_improvement_not_cleared() -> void:
	# Making another station WORSE moves the bottleneck without improving the line.
	var db: Dictionary = Autoplayer.fixture_db()
	db["skills"].append({"id": "s_nerf", "branch": "flow", "row": 1, "name_key": "x",
			"tip_key": "x", "cost": 0, "prereqs": [],
			"effects": [{"type": "stat_mult", "stat": "cycle_time",
					"scope": "station:alpha", "value": 10.0}]})
	var e = _engine(db)
	_run(e, 5.0)
	e.drain_events()
	assert_true(e.buy_skill("s_nerf"), "free nerf skill purchase")
	var events: Array = e.drain_events()
	assert_eq(_events_of(events, "bottleneck_cleared").size(), 0,
			"no cleared event when line pps did not improve")
	var changed: Array = _events_of(events, "bottleneck_changed")
	assert_eq(changed.size(), 1, "bottleneck did move")
	assert_eq(int(changed[0]["new_index"]), 0, "alpha now slowest")


func test_starved_blocked_statuses_and_buffer_cap() -> void:
	var e = _engine()
	_run(e, 90.0)
	# alpha (1.0 pps) feeds beta (0.5 proc): buffer before beta fills to cap -> alpha BLOCKED.
	assert_eq(int(e.get_station_view(0)["status"]), SimTypes.STATUS_BLOCKED, "alpha blocked")
	assert_eq(int(e.get_station_view(1)["status"]), SimTypes.STATUS_RUNNING, "bottleneck runs")
	assert_eq(int(e.get_station_view(2)["status"]), SimTypes.STATUS_STARVED, "gamma starved")
	var v1: Dictionary = e.get_station_view(1)
	assert_near(float(v1["buffer_in"]), 10.0, 0.2, "buffer filled to cap")
	assert_true(float(v1["buffer_in"]) <= float(v1["buffer_in_cap"]) + 1e-9, "cap respected")
	var v2: Dictionary = e.get_station_view(2)
	assert_true(float(v2["buffer_in"]) < 0.5, "starved buffer stays near empty")
	# Status transition events were queued along the way.
	var events: Array = e.drain_events()
	assert_true(_events_of(events, "station_status_changed").size() >= 3,
			"status transitions emitted")


func test_station0_infinite_raw_and_progress() -> void:
	var e = _engine()
	var v0: Dictionary = e.get_station_view(0)
	assert_near(float(v0["buffer_in"]), 0.0, 1e-9, "station 0 has no input buffer")
	assert_near(float(v0["buffer_in_cap"]), 0.0, 1e-9)
	_run(e, 0.5)
	assert_eq(int(e.get_station_view(0)["status"]), SimTypes.STATUS_RUNNING,
			"station 0 never starves")
	var p1: float = float(e.get_station_view(0)["progress"])
	_run(e, 0.3)
	var p2: float = float(e.get_station_view(0)["progress"])
	assert_true(p2 > p1, "progress advances while running (no wrap expected inside a cycle)")
	assert_true(p2 >= 0.0 and p2 <= 1.0)


func test_sell_pricing() -> void:
	var e = _engine()
	_run(e, 60.0)
	var t: Dictionary = e.debug_totals()
	# Contract-literal pricing: the last station sells at price_per_part x price mults.
	assert_near(e.money_earned.to_float(), float(t["sold"]) * 1.0, 1e-6 * float(t["sold"]) + 1e-9,
			"revenue = sold * price_per_part")
	assert_near(e.money.to_float(), 100.0 + e.money_earned.to_float(), 1e-6,
			"money = starting + earned (nothing spent)")
	var snap: Dictionary = e.get_stats_snapshot()
	assert_near(snap["rps"].to_float(), 0.4, 0.02, "snapshot rps at steady state")
	var sold_events: Array = _events_of(e.drain_events(), "part_sold")
	assert_true(sold_events.size() >= 30, "batched part_sold events (~1/s)")
	var total_count: float = 0.0
	for ev in sold_events:
		total_count += float(ev["count"])
	assert_near(total_count, float(t["sold"]), 0.5, "part_sold events account for sales")


func test_unlock_station_rules() -> void:
	var e = _engine()
	assert_false(e.unlock_station(0), "already unlocked")
	assert_false(e.unlock_station(99), "out of range")
	e.drain_events()
	assert_true(e.unlock_station(3), "next locked station affordable at 100 money")
	assert_near(e.money.to_float(), 50.0, 1e-9, "unlock cost deducted")
	var events: Array = e.drain_events()
	assert_eq(_events_of(events, "station_unlocked").size(), 1)
	var spent: Array = _events_of(events, "money_spent")
	assert_eq(spent.size(), 1)
	assert_eq(str(spent[0]["context"]), "unlock")
	assert_near(spent[0]["amount"].to_float(), 50.0, 1e-9)
	assert_false(e.unlock_station(3), "cannot unlock twice")
	assert_true(bool(e.get_station_view(3)["unlocked"]))
	# delta is fast with quality 1, so steady pps is unchanged by the longer line.
	assert_near(e.estimate_steady_pps(), 0.4, 1e-9)
	var snap: Dictionary = e.get_stats_snapshot()
	assert_eq(int(snap["bottleneck"]), 1, "beta still the bottleneck")


func test_unlock_out_of_order_rejected() -> void:
	var db: Dictionary = Autoplayer.fixture_db()
	db["stations"].append(Autoplayer._station("epsilon", 4, 75,
			{"cycle_time": 1.0, "uptime": 1.0, "quality": 1.0, "capacity": 1,
			"changeover_time": 0.0, "operator_count": 1}))
	db["balance"]["starting_money"] = 500.0
	var e = _engine(db)
	assert_false(e.unlock_station(4), "cannot skip over locked delta")
	assert_true(e.unlock_station(3))
	assert_true(e.unlock_station(4), "sequential unlock allowed")


func test_part_completed_events_gated_by_pps() -> void:
	var e = _engine()
	_run(e, 12.0)
	var parts: Array = _events_of(e.drain_events(), "part_completed")
	assert_true(parts.size() >= 5, "granular part events at low pps")
	# Gate closes when pps exceeds visual.part_event_max_pps.
	var db: Dictionary = Autoplayer.fixture_db()
	db["balance"]["visual"]["part_event_max_pps"] = 0.0
	var e2 = _engine(db)
	_run(e2, 12.0)
	assert_eq(_events_of(e2.drain_events(), "part_completed").size(), 0,
			"part events suppressed above the pps gate")


func test_scrap_events_and_totals() -> void:
	var e = _engine()
	_run(e, 60.0)
	var events: Array = e.drain_events()
	var scraps: Array = _events_of(events, "scrap_produced")
	assert_true(scraps.size() > 0, "beta (quality 0.8) produces scrap events")
	var from_beta := false
	var event_sum: float = 0.0
	for ev in scraps:
		event_sum += float(ev["amount"])
		if int(ev["station"]) == 1:
			from_beta = true
	assert_true(from_beta, "scrap comes from the quality-0.8 station")
	assert_true(e.scrap_total > 0.0)
	assert_near(event_sum, e.scrap_total, 0.2, "batched scrap events track the total")
	var v1: Dictionary = e.get_station_view(1)
	assert_near(float(v1["scrap_rate"]), 0.5 * 0.2, 0.02, "scrap_rate = proc * (1-q) at steady")


func test_value_add_pricing_flag() -> void:
	var db_va: Dictionary = Autoplayer.fixture_db()
	db_va["balance"]["value_add_pricing"] = true
	var flat = _engine()
	var va = SimEngineScript.new_game(db_va)
	_run(flat, 60.0)
	_run(va, 60.0)
	var flat_earned: float = flat.money_earned.to_float()
	assert_true(flat_earned > 0.0, "flat engine earned revenue")
	assert_near(va.money_earned.to_float(), flat_earned * 3.0,
			flat_earned * 1e-6 + 1e-9,
			"value-add price = flat x unlocked station count (3)")
	var next: int = va.next_locked_index()
	assert_true(va.estimate_unlock_delta_rps(next) > flat.estimate_unlock_delta_rps(next),
			"unlock valuation includes the (k+1)-station price bump")
