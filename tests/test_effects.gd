## Tests for the full skill-effect vocabulary (ARCHITECTURE.md §7): stat mods with scopes,
## global/price/cost multipliers, offline modifiers, KP passive, buffer caps, scrap refunds,
## starting money, the auto-buyer CI manager and unlock_feature.
extends "res://tests/test_framework.gd"

const Autoplayer = preload("res://tests/autoplayer.gd")
const SimEngineScript = preload("res://src/sim/sim_engine.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const BigNum = preload("res://src/sim/big_num.gd")


func _engine_with(skill_ids: Array, db: Dictionary = {}):
	if db.is_empty():
		db = Autoplayer.fixture_db()
	var e = SimEngineScript.new_game(db)
	e.kp = 100.0
	for id in skill_ids:
		if not e.buy_skill(id):
			fail("fixture skill purchase failed: %s" % id)
	return e


func _run(engine, seconds: float) -> void:
	var ticks: int = int(roundf(seconds / SimTypes.TICK_DT))
	for _i in ticks:
		engine.tick(SimTypes.TICK_DT)


func test_skill_purchase_rules() -> void:
	var e = SimEngineScript.new_game(Autoplayer.fixture_db())
	assert_false(e.buy_skill("s_global"), "no KP yet")
	e.kp = 1.0
	assert_false(e.buy_skill("s_capadd"), "prereq s_global not purchased")
	var st: Dictionary = e.get_skill_state("s_capadd")
	assert_false(bool(st["available"]))
	assert_true(bool(st["affordable"]))
	assert_eq(int(st["cost"]), 1)
	e.drain_events()
	assert_true(e.buy_skill("s_global"))
	assert_near(e.kp, 0.0, 1e-9, "KP spent")
	assert_false(e.buy_skill("s_global"), "cannot rebuy")
	var events: Array = e.drain_events()
	var purchased := false
	var kp_changed := false
	for ev in events:
		if str(ev["t"]) == "skill_purchased" and str(ev["node_id"]) == "s_global":
			purchased = true
		if str(ev["t"]) == "kaizen_points_changed":
			kp_changed = true
	assert_true(purchased, "skill_purchased event")
	assert_true(kp_changed, "kaizen_points_changed event")
	e.kp = 1.0
	assert_true(e.buy_skill("s_capadd"), "prereq met now")
	assert_true(bool(e.get_skill_state("s_capadd")["purchased"]))
	assert_false(e.buy_skill("nope"), "unknown id")


func test_global_throughput_mult() -> void:
	var e = _engine_with(["s_global"])
	assert_near(float(e.get_station_view(0)["throughput"]), 2.0, 1e-9, "alpha x2")
	assert_near(float(e.get_station_view(1)["throughput"]), 0.8, 1e-9, "beta x2")
	assert_near(e.estimate_steady_pps(), 0.8, 1e-9, "whole line scales")


func test_stat_mods_and_scopes() -> void:
	var e = _engine_with(["s_global", "s_capadd"])
	assert_near(float(e.get_station_view(0)["stats"]["capacity"]), 3.0, 1e-9,
			"stat_add capacity +2 on alpha")
	assert_near(float(e.get_station_view(1)["stats"]["capacity"]), 1.0, 1e-9,
			"station scope does not leak to beta")
	var e2 = _engine_with(["s_upall"])
	assert_near(float(e2.get_station_view(0)["stats"]["cycle_time"]), 0.5, 1e-9,
			"stat_mult all-scope on alpha")
	assert_near(float(e2.get_station_view(1)["stats"]["cycle_time"]), 1.0, 1e-9,
			"and on beta (2.0 * 0.5)")
	var e3 = _engine_with(["s_q1"])
	assert_near(float(e3.get_station_view(1)["stats"]["quality"]), 1.0, 1e-9,
			"stat_toward_one value 1.0 reaches exactly 1")
	assert_near(e3.estimate_steady_pps(), 0.5, 1e-9, "no yield loss anymore")


func test_price_mult() -> void:
	var e = _engine_with(["s_price"])
	_run(e, 30.0)
	var t: Dictionary = e.debug_totals()
	assert_near(e.money_earned.to_float(), float(t["sold"]) * 3.0,
			1e-6 * e.money_earned.to_float() + 1e-9,
			"revenue = sold * price_per_part * price_mult 3")


func test_upgrade_cost_mult_in_bundle() -> void:
	var e = _engine_with(["s_cost"])
	assert_near(e.get_upgrade_view(1, "speed", 1)["cost"].to_float(), 5.0, 1e-9)


func test_buffer_cap_mult() -> void:
	var e = _engine_with(["s_buf"])
	assert_near(float(e.get_station_view(1)["buffer_in_cap"]), 5.0, 1e-9, "10 * 0.5")
	_run(e, 60.0)
	assert_near(float(e.get_station_view(1)["buffer_in"]), 5.0, 0.2, "fills to reduced cap")
	assert_true(float(e.get_station_view(1)["buffer_in"]) <= 5.0 + 1e-9)


func test_kp_passive_per_min() -> void:
	var db: Dictionary = Autoplayer.fixture_db()
	db["milestones"] = []	# keep milestone KP grants out of the passive-income measurement
	db["achievements"] = []
	var e = _engine_with(["s_kp"], db)
	var kp0: float = e.kp
	e.drain_events()
	_run(e, 6.0)
	assert_near(e.kp - kp0, 6.0, 1e-6, "60 KP/min = 1 KP/s")
	var events: Array = e.drain_events()
	var kp_events: int = 0
	for ev in events:
		if str(ev["t"]) == "kaizen_points_changed":
			kp_events += 1
	assert_true(kp_events >= 5, "kp change events emitted about once per whole point")


func test_scrap_refund_frac() -> void:
	var base_e = _engine_with([])
	_run(base_e, 40.0)
	var e = _engine_with(["s_refund"])
	_run(e, 40.0)
	var t: Dictionary = e.debug_totals()
	# Refund recovers scrap_refund_frac of the flat part price per scrapped part.
	var expected_refund: float = float(t["scrap"]) * 1.0 * 0.5
	var sold_rev: float = float(t["sold"]) * 1.0
	assert_near(e.money_earned.to_float(), sold_rev + expected_refund,
			1e-6 * e.money_earned.to_float() + 1e-9, "refund = scrap * stage value * frac")
	assert_true(e.money_earned.to_float() > base_e.money_earned.to_float(),
			"refund skill earns more than baseline")


func test_starting_money_add_applies_on_prestige() -> void:
	var e = _engine_with(["s_start"])
	e.lifetime_parts = BigNum.from_float(1e6)
	assert_true(e.do_prestige())
	assert_near(e.money.to_float(), 100.0 + 500.0, 1e-9,
			"post-prestige money = starting_money + starting_money_add")


func test_offline_modifier_effects_in_bundle() -> void:
	# Full offline behavior is covered in test_offline; here we verify the skills wire up.
	var e = _engine_with(["s_offcap", "s_offrate"])
	_run(e, 20.0)
	var report: Dictionary = e.offline_progress(24.0 * 3600.0)
	assert_true(bool(report["capped"]))
	assert_near(float(report["seconds"]), 12.0 * 3600.0, 1e-6, "8h base + 4h skill")
	assert_near(report["parts"].to_float(), 0.4 * 12.0 * 3600.0 * 2.0, 1.0,
			"offline_rate_mult 2 doubles credited parts")


func test_auto_buyer_ci_manager() -> void:
	var e = _engine_with(["s_auto"])
	e.money = BigNum.from_float(200.0)
	e.drain_events()
	_run(e, 3.5)
	# Interval 1.0 s -> at least 3 purchase opportunities; bottleneck is beta so the best
	# delta-throughput/cost buys land there.
	assert_true(e.upgrade_purchase_count >= 3, "CI manager kept buying")
	var beta_levels: Dictionary = e.get_station_view(1)["upgrade_levels"]
	var beta_total: int = 0
	for uid in beta_levels:
		beta_total += int(beta_levels[uid])
	assert_true(beta_total >= 1, "purchases target the constraint")
	var events: Array = e.drain_events()
	var upgraded: int = 0
	for ev in events:
		if str(ev["t"]) == "station_upgraded":
			upgraded += 1
	assert_eq(upgraded, e.upgrade_purchase_count, "each auto-buy emitted its event")
	# Broke engine: auto-buyer just idles.
	var e2 = _engine_with(["s_auto"])
	e2.money = BigNum.zero()
	_run(e2, 3.0)
	assert_eq(e2.upgrade_purchase_count, 0, "no money, no buys, no errors")


func test_unlock_feature() -> void:
	var e = _engine_with(["s_feat"])
	assert_true(e.get_feature_unlocked("conveyor_vision"))
	assert_false(e.get_feature_unlocked("other_thing"))
	var snap: Dictionary = e.get_stats_snapshot()
	assert_true((snap["features"] as Array).has("conveyor_vision"), "snapshot exposes features")


func test_unknown_effect_type_is_ignored() -> void:
	var db: Dictionary = Autoplayer.fixture_db()
	db["skills"].append({"id": "s_bogus", "branch": "flow", "row": 1, "name_key": "x",
			"tip_key": "x", "cost": 0, "prereqs": [],
			"effects": [{"type": "warp_drive", "value": 9000.0}]})
	var e = SimEngineScript.new_game(db)
	assert_true(e.buy_skill("s_bogus"), "unknown effect purchase still succeeds")
	assert_near(float(e.get_station_view(0)["throughput"]), 1.0, 1e-9, "and changes nothing")
