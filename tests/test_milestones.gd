## Tests for milestone/achievement triggers: the full trigger vocabulary, one-time firing,
## KP grants + events, and persistence across prestige.
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


func _milestone_ids(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		if str(ev.get("t", "")) == "milestone_reached":
			out.append(str(ev["id"]))
	return out


func test_run_based_triggers_fire_once() -> void:
	var e = _engine()
	e.drain_events()
	_run(e, 150.0)	# ~58 parts sold at 0.4 pps -> parts/money/pps/oee milestones
	var events: Array = e.drain_events()
	var ids: Array = _milestone_ids(events)
	assert_true(ids.has("m_parts_10"), "lifetime_parts trigger")
	assert_true(ids.has("m_money_50"), "money_earned trigger (58 parts * 1.0 > 50)")
	assert_true(ids.has("m_pps"), "pps trigger")
	assert_true(ids.has("m_oee"), "oee trigger")
	assert_true(e.milestones_done.has("m_parts_10"))
	# KP granted: m_parts_10(2) + m_money_50(1) + m_pps(1) + m_oee(1) = 5.
	assert_near(e.kp, 5.0, 1e-9, "milestone KP granted")
	var kp_gained_sum: int = 0
	for ev in events:
		if str(ev["t"]) == "milestone_reached":
			kp_gained_sum += int(ev["kp_gained"])
	assert_eq(kp_gained_sum, 5)
	# Never re-fires.
	_run(e, 30.0)
	var again: Array = _milestone_ids(e.drain_events())
	assert_false(again.has("m_parts_10"), "one-time only")


func test_achievement_triggers() -> void:
	var e = _engine()
	e.drain_events()
	_run(e, 15.0)	# first part sells around t=3.6s
	var events: Array = e.drain_events()
	var ach: Array = []
	for ev in events:
		if str(ev["t"]) == "achievement_unlocked":
			ach.append(str(ev["id"]))
	assert_true(ach.has("ACH_FIRST_PART"), "achievement event uses EventBus signal name")
	assert_true(e.achievements_done.has("ACH_FIRST_PART"))
	assert_false(ach.has("ACH_UNLOCK_DELTA"), "delta not unlocked yet")
	e.unlock_station(3)
	e.tick(SimTypes.TICK_DT)
	var events2: Array = e.drain_events()
	var found := false
	for ev in events2:
		if str(ev.get("t", "")) == "achievement_unlocked" and str(ev["id"]) == "ACH_UNLOCK_DELTA":
			found = true
	assert_true(found, "station_unlocked achievement fires after unlock")


func test_station_unlocked_and_upgrade_count_triggers() -> void:
	var e = _engine()
	e.money = BigNum.from_float(1e6)
	e.drain_events()
	e.unlock_station(3)
	e.tick(SimTypes.TICK_DT)
	assert_true(_milestone_ids(e.drain_events()).has("m_unlock_delta"))
	e.buy_upgrade(0, "speed", 5)
	e.tick(SimTypes.TICK_DT)
	assert_true(_milestone_ids(e.drain_events()).has("m_upg5"), "upgrade_count counts levels")


func test_skill_count_trigger() -> void:
	var e = _engine()
	e.kp = 10.0
	e.drain_events()
	e.buy_skill("s_global")
	e.tick(SimTypes.TICK_DT)
	assert_false(_milestone_ids(e.drain_events()).has("m_skill2"), "one skill is not enough")
	e.buy_skill("s_price")
	e.tick(SimTypes.TICK_DT)
	assert_true(_milestone_ids(e.drain_events()).has("m_skill2"))


func test_bottleneck_cleared_count_trigger() -> void:
	var e = _engine()
	e.money = BigNum.from_float(1e6)
	_run(e, 5.0)
	e.drain_events()
	e.buy_upgrade(1, "speed", 10)	# clears beta (see test_line)
	e.tick(SimTypes.TICK_DT)
	assert_true(_milestone_ids(e.drain_events()).has("m_bnc"))


func test_zero_scrap_seconds_trigger() -> void:
	# Fixture beta scraps constantly: the streak never starts.
	var e = _engine()
	_run(e, 8.0)
	assert_false(e.milestones_done.has("m_zeroscrap"), "scrap keeps resetting the streak")
	assert_true(e.zero_scrap_seconds < 5.0)
	# Perfect quality via skill -> streak accrues while producing.
	var e2 = _engine()
	e2.kp = 1.0
	assert_true(e2.buy_skill("s_q1"))
	e2.drain_events()
	_run(e2, 8.0)
	assert_true(e2.zero_scrap_seconds >= 5.0, "streak accrued")
	assert_true(_milestone_ids(e2.drain_events()).has("m_zeroscrap"))


func test_prestige_count_trigger_and_persistence() -> void:
	var e = _engine()
	_run(e, 60.0)	# earn the early milestones first
	e.lifetime_parts = BigNum.from_float(1e6)
	e.drain_events()
	var done_before: int = e.milestones_done.size()
	assert_true(e.do_prestige())
	var ids: Array = _milestone_ids(e.drain_events())
	assert_true(ids.has("m_prest1"), "prestige_count milestone fires on prestige")
	assert_true(e.milestones_done.size() >= done_before + 1, "done set persists and grows")
	assert_true(e.milestones_done.has("m_parts_10"), "pre-prestige milestones stay done")
	_run(e, 30.0)
	assert_false(_milestone_ids(e.drain_events()).has("m_parts_10"),
			"no refire after prestige even though run counters reset")


func test_trigger_vocabulary_direct() -> void:
	# Unit-level checks of the evaluator, including the unknown-type guard.
	var MilestonesLib = preload("res://src/sim/milestones.gd")
	var facts := {
		"lifetime_parts": BigNum.from_float(150.0),
		"money_earned": BigNum.from_float(99.0),
		"pps": 2.0, "oee": 0.5,
		"bottleneck_cleared_count": 3, "upgrade_count": 10,
		"skill_count": 2, "prestige_count": 0,
		"unlocked_ids": {"alpha": true},
		"zero_scrap_seconds": 30.0,
	}
	assert_true(MilestonesLib.is_triggered({"type": "lifetime_parts", "value": 150}, facts))
	assert_false(MilestonesLib.is_triggered({"type": "lifetime_parts", "value": 151}, facts))
	assert_true(MilestonesLib.is_triggered({"type": "lifetime_parts", "value": {"m": 1.5, "e": 2}}, facts),
			"BigNum dict values accepted")
	assert_false(MilestonesLib.is_triggered({"type": "money_earned", "value": 100}, facts))
	assert_true(MilestonesLib.is_triggered({"type": "pps", "value": 2.0}, facts))
	assert_true(MilestonesLib.is_triggered({"type": "oee", "value": 0.5}, facts))
	assert_false(MilestonesLib.is_triggered({"type": "oee", "value": 0.51}, facts))
	assert_true(MilestonesLib.is_triggered({"type": "bottleneck_cleared_count", "value": 3}, facts))
	assert_true(MilestonesLib.is_triggered({"type": "upgrade_count", "value": 10}, facts))
	assert_true(MilestonesLib.is_triggered({"type": "skill_count", "value": 2}, facts))
	assert_false(MilestonesLib.is_triggered({"type": "prestige_count", "value": 1}, facts))
	assert_true(MilestonesLib.is_triggered({"type": "station_unlocked", "value": "alpha"}, facts))
	assert_false(MilestonesLib.is_triggered({"type": "station_unlocked", "value": "beta"}, facts))
	assert_true(MilestonesLib.is_triggered({"type": "zero_scrap_seconds", "value": 30}, facts))
	assert_false(MilestonesLib.is_triggered({"type": "made_up_trigger", "value": 1}, facts),
			"unknown trigger types never fire")
