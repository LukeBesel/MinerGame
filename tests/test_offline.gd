## Tests for closed-form offline progression: correctness vs live ticking, the cap
## (base + skill hours), rate multipliers, min_seconds gate, report shape — plus the
## perf budgets (8 h offline < 50 ms; 36 000 live ticks < 5 s wall).
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


func test_offline_matches_live_steady_state() -> void:
	# Live-run a warmed-up line, and offline-run an identical warmed-up line: same window,
	# nearly the same yield (offline uses the closed-form steady rate).
	var live = _engine()
	_run(live, 120.0)
	var live_parts0: float = live.lifetime_parts.to_float()
	_run(live, 600.0)
	var live_gain: float = live.lifetime_parts.to_float() - live_parts0
	var off = _engine()
	_run(off, 120.0)
	var report: Dictionary = off.offline_progress(600.0)
	var off_gain: float = report["parts"].to_float()
	assert_near(off_gain, live_gain, live_gain * 0.02 + 0.5,
			"closed-form offline tracks live simulation at steady state")
	assert_near(off_gain, 0.4 * 600.0, 2.0, "0.4 pps x 600 s")
	assert_near(report["money"].to_float(), off_gain * 1.0, 1e-6 * off_gain + 1e-9,
			"offline revenue at the flat sale price")
	assert_false(bool(report["capped"]))
	assert_near(float(report["seconds"]), 600.0, 1e-9)
	# State advanced too, conservation intact.
	var t: Dictionary = off.debug_totals()
	var balance_sum: float = float(t["sold"]) + float(t["scrap"]) + float(t["wip"])
	assert_near(float(t["started"]), balance_sum, 1e-6 * float(t["started"]) + 1e-9,
			"offline keeps parts started = sold + scrap + WIP")
	assert_true(float(t["scrap"]) > 0.0, "offline also accrues scrap (beta quality 0.8)")


func test_offline_cap_hours() -> void:
	var e = _engine()
	_run(e, 30.0)
	var report: Dictionary = e.offline_progress(100.0 * 3600.0)
	assert_true(bool(report["capped"]))
	assert_near(float(report["seconds"]), 8.0 * 3600.0, 1e-6, "capped at 8 h base")
	assert_near(report["parts"].to_float(), 0.4 * 8.0 * 3600.0, 1.0)
	# Skill adds cap hours.
	var e2 = _engine()
	e2.kp = 5.0
	assert_true(e2.buy_skill("s_offcap"))
	var r2: Dictionary = e2.offline_progress(100.0 * 3600.0)
	assert_near(float(r2["seconds"]), 12.0 * 3600.0, 1e-6, "8 + 4 skill hours")
	assert_true(bool(r2["capped"]))


func test_offline_rate_mult() -> void:
	var e = _engine()
	e.kp = 5.0
	assert_true(e.buy_skill("s_offrate"))
	var report: Dictionary = e.offline_progress(1000.0)
	assert_near(report["parts"].to_float(), 0.4 * 1000.0 * 2.0, 1.0, "rate x2")
	assert_near(float(report["seconds"]), 1000.0, 1e-9, "rate boosts yield, not the clock")


func test_offline_min_seconds_gate() -> void:
	var e = _engine()
	var money_before: float = e.money.to_float()
	var report: Dictionary = e.offline_progress(30.0)	# fixture min_seconds = 60
	assert_near(float(report["seconds"]), 0.0, 1e-9)
	assert_true(report["parts"].is_zero())
	assert_true(report["money"].is_zero())
	assert_near(e.money.to_float(), money_before, 1e-9, "nothing applied under the gate")


func test_offline_kp_passive_and_milestones() -> void:
	var e = _engine()
	e.kp = 5.0
	assert_true(e.buy_skill("s_kp"))	# 1 KP/s passive
	var kp_before: float = e.kp
	e.drain_events()
	var report: Dictionary = e.offline_progress(600.0)
	assert_near(float(report["kp"]), 600.0, 1e-6, "passive KP over the credited window")
	assert_true(e.kp >= kp_before + 600.0, "applied to state (plus milestone grants)")
	var ids: Array = []
	for ev in e.drain_events():
		if str(ev["t"]) == "milestone_reached":
			ids.append(str(ev["id"]))
	assert_true(ids.has("m_parts_10"), "big offline jumps trigger milestones (240 parts)")
	assert_true(ids.has("m_money_50"))


func test_offline_respects_current_bottleneck() -> void:
	# Upgrading the bottleneck first must raise the offline rate accordingly.
	var e = _engine()
	e.money = BigNum.from_float(1e6)
	assert_true(e.buy_upgrade(1, "speed", 5))	# beta proc 0.5 -> 0.5/0.9^5 = 0.847; tp 0.677
	var expected: float = e.estimate_steady_pps()
	assert_true(expected > 0.5, "line got faster")
	var report: Dictionary = e.offline_progress(1000.0)
	assert_near(report["parts"].to_float(), expected * 1000.0, 1.0)


func test_offline_perf_under_50ms() -> void:
	var e = _engine()
	_run(e, 10.0)
	var t0: int = Time.get_ticks_usec()
	var report: Dictionary = e.offline_progress(8.0 * 3600.0)
	var elapsed_us: int = Time.get_ticks_usec() - t0
	assert_true(report["parts"].to_float() > 0.0)
	assert_true(elapsed_us < 50000, "8 h offline took %d us (budget 50 ms)" % elapsed_us)
	# "Any duration": a decade offline is the same O(1) math.
	var e2 = _engine()
	t0 = Time.get_ticks_usec()
	e2.offline_progress(10.0 * 365.0 * 24.0 * 3600.0)
	elapsed_us = Time.get_ticks_usec() - t0
	assert_true(elapsed_us < 50000, "10 y offline took %d us (budget 50 ms)" % elapsed_us)


func test_tick_perf_36000_ticks_under_5s() -> void:
	# One busy sim-hour (auto-buyer on, milestones pending, money flowing) in < 5 s wall.
	var e = _engine()
	e.kp = 100.0
	assert_true(e.buy_skill("s_auto"))
	e.money = BigNum.from_float(1e12)
	var t0: int = Time.get_ticks_msec()
	for _i in 36000:
		e.tick(0.1)
		if e.drain_events().size() > 0:
			pass	# drain like the Game bridge would
	var elapsed_ms: int = Time.get_ticks_msec() - t0
	print("  perf: 36000 ticks in %d ms" % elapsed_ms)
	assert_true(elapsed_ms < 5000, "36000 ticks took %d ms (budget 5000)" % elapsed_ms)
	assert_true(e.lifetime_parts.to_float() > 0.0, "the hour actually produced")
