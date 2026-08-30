## Tests for SimEngine rush orders: spawn gating (time / cooldown / min_pps),
## deterministic weighted rotation, required-parts scaling, progress/success/reward math,
## timeout without penalty, offline cancellation, and save roundtrip.
extends "res://tests/test_framework.gd"

const Autoplayer = preload("res://tests/autoplayer.gd")
const SimEngineScript = preload("res://src/sim/sim_engine.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const BigNum = preload("res://src/sim/big_num.gd")


## Fixture orders config layered on Autoplayer.fixture_db() (steady pps 0.4, price 1.0):
## alpha_order: 100 s window -> required 0.4*100*0.5 = 20; beta_order: 40 s -> 8 -> min 10.
static func _orders_cfg() -> Dictionary:
	return {
		"schema_version": 1,
		"start_after_seconds": 5.0,
		"cooldown_seconds": 10.0,
		"min_pps": 0.1,
		"duration_fraction_of_capacity": 0.5,
		"templates": [
			{"id": "alpha_order", "name_key": "order.alpha", "seconds": 100.0,
					"reward_mult": 2.0, "kp_bonus": 1, "weight": 2},
			{"id": "beta_order", "name_key": "order.beta", "seconds": 40.0,
					"reward_mult": 1.5, "kp_bonus": 0, "weight": 1},
		],
	}


func _db_with_orders(cfg: Dictionary = {}) -> Dictionary:
	var db: Dictionary = Autoplayer.fixture_db()
	db["orders"] = _orders_cfg() if cfg.is_empty() else cfg
	return db


func _engine(db: Dictionary = {}):
	if db.is_empty():
		db = _db_with_orders()
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


func test_no_orders_config_means_no_orders() -> void:
	var e = SimEngineScript.new_game(Autoplayer.fixture_db())
	_run(e, 30.0)
	assert_true(e.get_order_view().is_empty(), "no config -> no order ever")
	var snap: Dictionary = e.get_stats_snapshot()
	assert_true(snap.has("order"), "snapshot carries the additive order key")
	assert_true((snap["order"] as Dictionary).is_empty(), "empty order view when disabled")
	var events: Array = e.drain_events()
	assert_eq(_events_of(events, "order_started").size(), 0)


func test_spawn_gated_by_start_after_seconds() -> void:
	var e = _engine()
	_run(e, 4.5)
	assert_true(e.get_order_view().is_empty(), "no order before start_after_seconds")
	assert_eq(_events_of(e.drain_events(), "order_started").size(), 0)
	_run(e, 1.0)
	var view: Dictionary = e.get_order_view()
	assert_false(view.is_empty(), "order spawns once the opening gate passes")
	assert_eq(str(view["id"]), "alpha_order", "rotation starts at the first weighted slot")
	var started: Array = _events_of(e.drain_events(), "order_started")
	assert_eq(started.size(), 1, "order_started queued exactly once")
	assert_eq(str(started[0]["id"]), "alpha_order")


func test_spawn_gated_by_min_pps() -> void:
	var cfg: Dictionary = _orders_cfg()
	cfg["min_pps"] = 5.0	# fixture line peaks at 0.4 pps
	var e = _engine(_db_with_orders(cfg))
	_run(e, 30.0)
	assert_true(e.get_order_view().is_empty(), "no order while pps < min_pps")
	assert_eq(_events_of(e.drain_events(), "order_started").size(), 0)


func test_required_parts_scaling_and_floor() -> void:
	var e = _engine()
	_run(e, 6.0)
	var view: Dictionary = e.get_order_view()
	# steady 0.4 pps x 100 s x 0.5 fraction = 20 — beatable at the pace already sustained.
	assert_near(float(view["required"]), 20.0, 1e-9, "required = steady pps x seconds x fraction")
	assert_near(float(view["seconds_left"]), 100.0, 1.5)	# spawned ~1 s of ticks ago
	assert_near(float(view["reward_mult"]), 2.0, 1e-9)
	assert_near(view["reward_preview"].to_float(), 20.0, 1e-9,
			"preview = required x price x (mult - 1) = 20 x 1 x 1")
	for key in ["id", "name", "required", "progress", "seconds_left", "reward_mult", "reward_preview"]:
		assert_true(view.has(key), "order view key %s" % key)
	var snap: Dictionary = e.get_stats_snapshot()
	assert_eq(str((snap["order"] as Dictionary).get("id", "")), "alpha_order",
			"snapshot order matches the live view")
	# Floor: a faster line raises required; a tiny ask still floors at 10 parts.
	var e2 = _engine()
	e2.money = BigNum.from_float(1e6)
	assert_true(e2.buy_upgrade(1, "speed", 10))	# steady 0.4 -> 0.8 (alpha-bound)
	assert_near(e2.estimate_steady_pps(), 0.8, 0.01)
	_run(e2, 6.0)
	var v2: Dictionary = e2.get_order_view()
	assert_near(float(v2["required"]), roundf(e2.estimate_steady_pps() * 100.0 * 0.5), 1.0,
			"required scales with the CURRENT steady rate")
	var cfg: Dictionary = _orders_cfg()
	cfg["duration_fraction_of_capacity"] = 0.05	# 0.4 x 100 x 0.05 = 2 -> floor 10
	var e3 = _engine(_db_with_orders(cfg))
	_run(e3, 6.0)
	assert_near(float(e3.get_order_view()["required"]), 10.0, 1e-9, "minimum 10 parts")


func test_progress_success_reward_and_kp_bonus() -> void:
	# Milestones cleared so the only KP source in this test is the order bonus.
	var db: Dictionary = _db_with_orders()
	db["milestones"] = []
	var e = _engine(db)
	_run(e, 6.0)
	assert_false(e.get_order_view().is_empty())
	var kp_before: float = e.kp
	_run(e, 10.0)
	var mid: Dictionary = e.get_order_view()
	assert_true(float(mid["progress"]) > 3.0, "progress counts sold parts while active")
	assert_true(float(mid["seconds_left"]) < 95.0, "clock runs down")
	_run(e, 42.0)	# 20 required / 0.4 pps = 50 s after spawn; done by t=58, cooldown till ~65
	assert_true(e.get_order_view().is_empty(), "order completed and cleared")
	var events: Array = e.drain_events()
	var done: Array = _events_of(events, "order_completed")
	assert_eq(done.size(), 1, "order_completed queued")
	assert_eq(str(done[0]["id"]), "alpha_order")
	assert_near(done[0]["reward"].to_float(), 20.0, 1e-9,
			"reward = required x sale price x (reward_mult - 1)")
	assert_eq(_events_of(events, "order_failed").size(), 0)
	assert_near(e.kp, kp_before + 1.0, 1e-9, "kp_bonus granted on success")
	# The bonus really landed in the wallet: earned = sales + reward.
	var t: Dictionary = e.debug_totals()
	assert_near(e.money_earned.to_float(), float(t["sold"]) * 1.0 + 20.0,
			1e-6 * e.money_earned.to_float() + 1e-6, "money_earned = sales + order bonus")


func test_timeout_fails_without_penalty_and_cooldown_restarts() -> void:
	var cfg: Dictionary = _orders_cfg()
	# 20 s window, floor of 10 required, line sells 0.4/s -> only 8 parts: guaranteed miss.
	cfg["templates"] = [{"id": "doomed", "name_key": "order.doomed", "seconds": 20.0,
			"reward_mult": 2.0, "kp_bonus": 1, "weight": 1}]
	var db: Dictionary = _db_with_orders(cfg)
	db["milestones"] = []	# keep milestone KP out of the no-penalty assertions
	var e = _engine(db)
	_run(e, 6.0)
	assert_false(e.get_order_view().is_empty(), "doomed order spawned")
	var kp_before: float = e.kp
	_run(e, 21.0)
	assert_true(e.get_order_view().is_empty(), "order expired")
	var events: Array = e.drain_events()
	var failed: Array = _events_of(events, "order_failed")
	assert_eq(failed.size(), 1, "order_failed queued")
	assert_eq(str(failed[0]["id"]), "doomed")
	assert_eq(_events_of(events, "order_completed").size(), 0)
	assert_near(e.kp, kp_before, 1e-9, "no KP change on a miss")
	var t: Dictionary = e.debug_totals()
	assert_near(e.money_earned.to_float(), float(t["sold"]) * 1.0,
			1e-6 * e.money_earned.to_float() + 1e-6, "no penalty: earned = plain sales")
	# Cooldown (10 s) gates the next spawn.
	_run(e, 5.0)
	assert_true(e.get_order_view().is_empty(), "still cooling down")
	_run(e, 6.0)
	assert_false(e.get_order_view().is_empty(), "next order after the cooldown")


func test_deterministic_weighted_rotation() -> void:
	var cfg: Dictionary = _orders_cfg()
	cfg["start_after_seconds"] = 0.0
	cfg["cooldown_seconds"] = 0.5
	# 1 s windows that always miss (floor 10 > 0.4 sold) -> rapid deterministic cycling.
	cfg["templates"] = [
		{"id": "common", "name_key": "order.common", "seconds": 1.0,
				"reward_mult": 1.5, "kp_bonus": 0, "weight": 2},
		{"id": "rare", "name_key": "order.rare", "seconds": 1.0,
				"reward_mult": 3.0, "kp_bonus": 0, "weight": 1},
	]
	var e = _engine(_db_with_orders(cfg))
	_run(e, 8.0)
	var ids: Array = []
	for ev in _events_of(e.drain_events(), "order_started"):
		ids.append(str(ev["id"]))
	assert_true(ids.size() >= 5, "several orders cycled (got %d)" % ids.size())
	var expected := ["common", "common", "rare", "common", "common"]
	for i in 5:
		assert_eq(ids[i], expected[i], "weighted rotation slot %d" % i)
	# Identical engines produce the identical sequence — zero RNG.
	var e2 = _engine(_db_with_orders(cfg))
	_run(e2, 8.0)
	var ids2: Array = []
	for ev in _events_of(e2.drain_events(), "order_started"):
		ids2.append(str(ev["id"]))
	assert_eq(ids2, ids, "rotation is deterministic across runs")


func test_offline_cancels_silently_and_restarts_cooldown() -> void:
	var e = _engine()
	_run(e, 6.0)
	assert_false(e.get_order_view().is_empty(), "order active before going offline")
	e.drain_events()
	var report: Dictionary = e.offline_progress(600.0)
	assert_true(report["parts"].to_float() > 0.0, "offline actually credited")
	assert_true(e.get_order_view().is_empty(), "active order cancelled by offline")
	var events: Array = e.drain_events()
	assert_eq(_events_of(events, "order_failed").size(), 0, "silent cancel — no failed event")
	assert_eq(_events_of(events, "order_completed").size(), 0, "and no completion either")
	_run(e, 5.0)
	assert_true(e.get_order_view().is_empty(), "cooldown restarted after offline")
	_run(e, 6.0)
	assert_false(e.get_order_view().is_empty(), "orders resume once the cooldown elapses")
	# Under the min_seconds gate offline is a no-op and must NOT touch the running order.
	var e2 = _engine()
	_run(e2, 6.0)
	var before: Dictionary = e2.get_order_view()
	e2.offline_progress(10.0)	# fixture offline.min_seconds = 60
	assert_eq(str(e2.get_order_view().get("id", "")), str(before["id"]),
			"sub-minute absence leaves the order running")


func test_save_roundtrip_preserves_order_state_and_rotation() -> void:
	var e = _engine()
	_run(e, 6.0)
	_run(e, 10.0)	# accrue some progress
	var view: Dictionary = e.get_order_view()
	assert_false(view.is_empty())
	var state: Dictionary = e.serialize()
	var json_state: Variant = JSON.parse_string(JSON.stringify(state))
	assert_eq(typeof(json_state), TYPE_DICTIONARY, "order state serializes to pure JSON")
	var e2 = _engine()
	assert_true(e2.load_state(json_state))
	var v2: Dictionary = e2.get_order_view()
	assert_eq(str(v2["id"]), str(view["id"]), "active order id survives")
	assert_near(float(v2["required"]), float(view["required"]), 1e-6)
	assert_near(float(v2["progress"]), float(view["progress"]), 1e-6)
	assert_near(float(v2["seconds_left"]), float(view["seconds_left"]), 1e-6)
	assert_near(float(v2["reward_mult"]), float(view["reward_mult"]), 1e-9)
	assert_eq(int(e2.order_rotation), int(e.order_rotation), "rotation counter survives")
	assert_eq(e2.drain_events().size(), 0, "loading queues no order events")
	# The resumed order still completes normally.
	_run(e2, 60.0)
	var done: Array = _events_of(e2.drain_events(), "order_completed")
	assert_eq(done.size(), 1, "resumed order completed after load")
	# Old saves without order keys load cleanly with orders idle.
	var legacy: Dictionary = e.serialize()
	legacy.erase("order_rotation")
	legacy.erase("order_ready_at")
	legacy.erase("order_active")
	var e3 = _engine()
	assert_true(e3.load_state(legacy), "pre-orders save still loads")
	assert_true(e3.get_order_view().is_empty())
	assert_eq(int(e3.order_rotation), 0)


func test_prestige_drops_order_silently() -> void:
	var cfg: Dictionary = _orders_cfg()
	cfg["start_after_seconds"] = 0.0
	var db: Dictionary = _db_with_orders(cfg)
	db["balance"]["prestige"]["min_lifetime_parts"] = 10.0
	db["balance"]["prestige"]["divisor"] = 4.0	# 16 parts by t=40 -> cip_gain 2
	var e = _engine(db)
	_run(e, 40.0)	# well past the 10-part gate; an order is active (100 s window)
	assert_false(e.get_order_view().is_empty(), "order running before prestige")
	e.drain_events()
	assert_true(e.do_prestige())
	assert_true(e.get_order_view().is_empty(), "prestige clears the in-flight order")
	var events: Array = e.drain_events()
	assert_eq(_events_of(events, "order_failed").size(), 0, "no failed event on prestige")
	assert_eq(_events_of(events, "order_completed").size(), 0)
