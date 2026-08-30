## Tests for the Kaizen Event (prestige): CIP formula, gain accumulation, multiplier,
## reset-vs-persist rules, prestige view, and serialize/load_state round-trips.
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


func test_cip_formula() -> void:
	# fixture: min_lifetime_parts 1000, divisor 100, exponent 0.5.
	var e = _engine()
	var pv: Dictionary = e.get_prestige_view()
	assert_eq(int(pv["cip_gain"]), 0)
	assert_false(bool(pv["can_prestige"]))
	assert_near(pv["min_parts"].to_float(), 1000.0, 1e-9)
	e.lifetime_parts = BigNum.from_float(999.0)
	assert_false(bool(e.get_prestige_view()["can_prestige"]), "below min parts")
	e.lifetime_parts = BigNum.from_float(1000.0)
	pv = e.get_prestige_view()
	assert_true(bool(pv["can_prestige"]))
	assert_eq(int(pv["cip_gain"]), 3, "floor(sqrt(1000/100)) = floor(3.162)")
	assert_near(float(pv["multiplier_now"]), 1.0, 1e-9)
	assert_near(float(pv["multiplier_after"]), 1.3, 1e-9)
	e.lifetime_parts = BigNum.from_float(160000.0)
	assert_eq(int(e.get_prestige_view()["cip_gain"]), 40, "floor(sqrt(1600))")
	e.lifetime_parts = BigNum.make(1.0, 10)	# (1e10/100)^0.5 = 1e4
	assert_eq(int(e.get_prestige_view()["cip_gain"]), 10000, "exact power-of-ten case")


func test_prestige_gain_is_total_minus_earned() -> void:
	var e = _engine()
	e.lifetime_parts = BigNum.from_float(1000.0)
	assert_true(e.do_prestige())
	assert_eq(e.cip, 3)
	assert_eq(e.prestige_count, 1)
	# Lifetime persists; immediately after, total(1000) - earned(3) = 0 -> cannot re-prestige.
	assert_near(e.lifetime_parts.to_float(), 1000.0, 1e-9, "lifetime parts persist")
	var pv: Dictionary = e.get_prestige_view()
	assert_eq(int(pv["cip_gain"]), 0)
	assert_false(bool(pv["can_prestige"]), "zero-gain prestige is blocked")
	assert_false(e.do_prestige())
	# Grow to 2500 lifetime: total floor(sqrt(25)) = 5 -> gain 2.
	e.lifetime_parts = BigNum.from_float(2500.0)
	pv = e.get_prestige_view()
	assert_eq(int(pv["cip_gain"]), 2)
	assert_true(e.do_prestige())
	assert_eq(e.cip, 5)
	assert_eq(e.prestige_count, 2)


func test_prestige_resets_run_and_keeps_meta() -> void:
	var e = _engine()
	e.kp = 20.0
	assert_true(e.buy_skill("s_price"))
	e.money = BigNum.from_float(1e6)
	assert_true(e.buy_upgrade(0, "speed", 5))
	assert_true(e.unlock_station(3))
	_run(e, 60.0)
	var scrap_before: float = e.scrap_total
	var time_before: float = e.time_played
	var milestones_before: int = e.milestones_done.size()
	var kp_before: float = e.kp
	assert_true(scrap_before > 0.0)
	e.lifetime_parts = BigNum.from_float(1e6)
	e.drain_events()
	assert_true(e.do_prestige())
	# --- resets ---
	assert_near(e.money.to_float(), 100.0, 1e-9, "money back to starting")
	assert_eq(int(e.get_station_view(0)["upgrade_levels"]["speed"]), 0, "levels reset")
	assert_false(bool(e.get_station_view(3)["unlocked"]), "delta locked again")
	assert_near(float(e.get_station_view(1)["buffer_in"]), 0.0, 1e-9, "buffers flushed")
	assert_near(e.pps, 0.0, 1e-9)
	assert_near(e.oee, 0.0, 1e-9, "OEE window reset")
	# --- persists ---
	assert_true(e.purchased_skills.has("s_price"), "skill tree persists")
	assert_near(e.kp, kp_before + 5.0, 1e-9, "KP persists (+5 from the prestige milestone)")
	assert_eq(e.cip, 100, "sqrt(1e6/100) = 100 CIP")
	assert_near(e.scrap_total, scrap_before, 1e-9, "lifetime scrap persists")
	assert_near(e.time_played, time_before, 1e-9, "time played persists")
	assert_eq(e.milestones_done.size(), milestones_before + 1,
			"milestones persist (+ the new prestige milestone)")
	assert_true(e.milestones_done.has("m_parts_10"), "earlier milestones still done")
	assert_near(e.lifetime_parts.to_float(), 1e6, 1e-3, "lifetime parts persist")
	# --- events + multiplier ---
	var events: Array = e.drain_events()
	var prestige_ev: Dictionary = {}
	var bn_ev: Dictionary = {}
	for ev in events:
		if str(ev["t"]) == "prestige_performed":
			prestige_ev = ev
		elif str(ev["t"]) == "bottleneck_changed":
			bn_ev = ev
	assert_eq(int(prestige_ev.get("cip_gained", -1)), 100)
	assert_near(float(prestige_ev.get("new_multiplier", 0.0)), 11.0, 1e-9, "1 + 100*0.1")
	assert_eq(int(bn_ev.get("old_index", -99)), -1, "bottleneck re-detected fresh after reset")
	# CIP multiplier applies to throughput: alpha 1.0 * 11 (price skill persists, x3 price).
	assert_near(float(e.get_station_view(0)["throughput"]), 11.0, 1e-6)
	assert_near(e.estimate_steady_pps(), 0.4 * 11.0, 1e-6)
	var snap: Dictionary = e.get_stats_snapshot()
	assert_near(float(snap["cip_mult"]), 11.0, 1e-9)
	assert_eq(int(snap["prestige_count"]), 1)


func test_serialize_roundtrip() -> void:
	var db: Dictionary = Autoplayer.fixture_db()
	var e = _engine(db)
	e.kp = 10.0
	assert_true(e.buy_skill("s_global"))
	e.money = BigNum.from_float(5000.0)
	assert_true(e.buy_upgrade(1, "speed", 3))
	assert_true(e.unlock_station(3))
	_run(e, 45.0)
	var state: Dictionary = e.serialize()
	# BigNums serialize as {"m","e"} dicts.
	assert_true(state["money"] is Dictionary and state["money"].has("m") and state["money"].has("e"))
	assert_true(state["lifetime_parts"] is Dictionary)
	# JSON round-trip survival (what SaveManager will do to it).
	var json_state: Variant = JSON.parse_string(JSON.stringify(state))
	assert_true(typeof(json_state) == TYPE_DICTIONARY, "state is pure JSON data")
	var e2 = SimEngineScript.new_game(Autoplayer.fixture_db())
	assert_true(e2.load_state(json_state))
	assert_near(e2.money.to_float(), e.money.to_float(), 1e-6)
	assert_near(e2.kp, e.kp, 1e-9)
	assert_eq(e2.cip, e.cip)
	assert_near(e2.lifetime_parts.to_float(), e.lifetime_parts.to_float(), 1e-6)
	assert_eq(int(e2.get_station_view(1)["upgrade_levels"]["speed"]), 3)
	assert_true(bool(e2.get_station_view(3)["unlocked"]))
	assert_true(e2.purchased_skills.has("s_global"))
	assert_near(float(e2.get_station_view(1)["buffer_in"]), float(e.get_station_view(1)["buffer_in"]), 1e-6)
	assert_eq(e2.bottleneck, e.bottleneck)
	assert_near(e2.estimate_steady_pps(), e.estimate_steady_pps(), 1e-9)
	assert_eq(e2.drain_events().size(), 0, "loading queues no events")
	# Conservation counters survive: run both and they stay consistent.
	_run(e2, 10.0)
	var t: Dictionary = e2.debug_totals()
	var balance_sum: float = float(t["sold"]) + float(t["scrap"]) + float(t["wip"])
	assert_near(float(t["started"]), balance_sum, 1e-6 * float(t["started"]) + 1e-9,
			"conservation intact after load")


func test_load_state_rejects_garbage() -> void:
	var db: Dictionary = Autoplayer.fixture_db()
	db["stations"].append(Autoplayer._station("epsilon", 4, 75,
			{"cycle_time": 1.0, "uptime": 1.0, "quality": 1.0, "capacity": 1,
			"changeover_time": 0.0, "operator_count": 1}))
	var e = _engine(db)
	assert_false(e.load_state({}))
	assert_false(e.load_state({"version": 99}), "future save versions rejected")
	# Unknown ids and out-of-range values are dropped/clamped, not fatal.
	var weird := {
		"version": 1,
		"money": {"m": 5.0, "e": 1},
		"purchased_skills": ["s_global", "not_a_skill"],
		"stations": [
			{"id": "alpha", "unlocked": true, "levels": {"speed": 3, "bogus": 9}, "buffer": 1e9},
			{"id": "beta", "unlocked": true, "levels": {}, "buffer": -5.0},
			{"id": "epsilon", "unlocked": true, "levels": {}, "buffer": 0.0},
		],
	}
	assert_true(e.load_state(weird))
	assert_true(e.purchased_skills.has("s_global"))
	assert_false(e.purchased_skills.has("not_a_skill"), "unknown skill dropped")
	assert_eq(int(e.get_station_view(0)["upgrade_levels"]["speed"]), 3)
	assert_false(e.get_station_view(0)["upgrade_levels"].has("bogus"))
	assert_false(bool(e.get_station_view(3)["unlocked"]), "delta stays locked (not in save)")
	assert_false(bool(e.get_station_view(4)["unlocked"]),
			"epsilon unlock behind locked delta is normalized away (line stays a prefix)")
	assert_true(float(e.get_station_view(1)["buffer_in"]) >= 0.0, "negative buffer clamped")
	assert_true(float(e.get_station_view(1)["buffer_in"]) <= float(e.get_station_view(1)["buffer_in_cap"]))
	assert_near(e.money.to_float(), 50.0, 1e-9)
	# Engine still ticks fine afterwards.
	_run(e, 2.0)
	assert_true(e.pps >= 0.0)


func test_prestige_view_shape() -> void:
	var e = _engine()
	var pv: Dictionary = e.get_prestige_view()
	for key in ["cip_current", "cip_gain", "multiplier_now", "multiplier_after",
			"lifetime_parts", "min_parts", "can_prestige"]:
		assert_true(pv.has(key), "prestige view key %s" % key)
	assert_eq(int(pv["cip_current"]), 0)
