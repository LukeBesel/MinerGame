## Tests for upgrade cost curves: per-level pricing, exact geometric bulk sums, BUY_MAX
## closed-form boundaries, max_level clamps, buy-multiplier semantics, cost-mult skills.
extends "res://tests/test_framework.gd"

const Autoplayer = preload("res://tests/autoplayer.gd")
const SimEngineScript = preload("res://src/sim/sim_engine.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const UpgradeMath = preload("res://src/sim/upgrade_math.gd")
const BigNum = preload("res://src/sim/big_num.gd")


func _engine(db: Dictionary = {}):
	if db.is_empty():
		db = Autoplayer.fixture_db()
	return SimEngineScript.new_game(db)


func _manual_bulk(base: float, growth: float, level: int, count: int) -> float:
	var sum: float = 0.0
	for i in count:
		sum += base * pow(growth, float(level + i))
	return sum


func test_level_cost_curve() -> void:
	var c0 = UpgradeMath.level_cost(10.0, 1.10, 0)
	assert_near(c0.to_float(), 10.0, 1e-9, "level 0 costs base")
	var c5 = UpgradeMath.level_cost(10.0, 1.10, 5)
	assert_near(c5.to_float(), 10.0 * pow(1.10, 5.0), 1e-6)
	var c100 = UpgradeMath.level_cost(10.0, 1.15, 100)
	assert_near(c100.to_float() / (10.0 * pow(1.15, 100.0)), 1.0, 1e-9, "high level stays exact")
	var cm = UpgradeMath.level_cost(10.0, 1.10, 3, 0.5)
	assert_near(cm.to_float(), 5.0 * pow(1.10, 3.0), 1e-6, "cost multiplier applies")


func test_bulk_cost_closed_form() -> void:
	for level in [0, 3, 17]:
		for count in [1, 2, 10, 37]:
			var closed = UpgradeMath.bulk_cost(10.0, 1.10, level, count)
			var manual: float = _manual_bulk(10.0, 1.10, level, count)
			assert_near(closed.to_float() / manual, 1.0, 1e-9,
					"bulk L%d x%d matches manual sum" % [level, count])
	# Flat growth degenerates to base * count.
	var flat = UpgradeMath.bulk_cost(10.0, 1.0, 5, 7)
	assert_near(flat.to_float(), 70.0, 1e-9, "growth 1.0 -> linear pricing")
	assert_true(UpgradeMath.bulk_cost(10.0, 1.1, 0, 0).is_zero(), "zero count is free")


func test_max_affordable_exact_boundaries() -> void:
	# Exactly affording n levels must return n; a hair less must return n-1.
	for n in [1, 2, 5, 23, 100]:
		var exact = UpgradeMath.bulk_cost(10.0, 1.10, 4, n)
		assert_eq(UpgradeMath.max_affordable(10.0, 1.10, 4, exact), n,
				"exact budget buys exactly %d" % n)
		var less = exact.sub(BigNum.from_float(0.01))
		assert_eq(UpgradeMath.max_affordable(10.0, 1.10, 4, less), n - 1,
				"a cent less buys %d" % (n - 1))
	assert_eq(UpgradeMath.max_affordable(10.0, 1.10, 0, BigNum.from_float(9.99)), 0,
			"cannot afford one")
	assert_eq(UpgradeMath.max_affordable(10.0, 1.0, 0, BigNum.from_float(105.0)), 10,
			"flat growth: floor(money/base)")
	# Huge budget stays consistent (log-space path, thousands of levels).
	var rich = BigNum.make(1.0, 120)
	var n_max: int = UpgradeMath.max_affordable(10.0, 1.10, 0, rich)
	assert_true(UpgradeMath.bulk_cost(10.0, 1.10, 0, n_max).le(rich), "n_max affordable")
	assert_true(UpgradeMath.bulk_cost(10.0, 1.10, 0, n_max + 1).gt(rich), "n_max+1 is not")


func test_upgrade_view_costs() -> void:
	var e = _engine()
	var v: Dictionary = e.get_upgrade_view(0, "speed", 1)
	assert_near(v["cost"].to_float(), 10.0, 1e-9)
	assert_eq(v["count"], 1)
	assert_true(bool(v["affordable"]))
	assert_false(bool(v["maxed"]))
	var v10: Dictionary = e.get_upgrade_view(0, "speed", 10)
	assert_near(v10["cost"].to_float(), _manual_bulk(10.0, 1.10, 0, 10), 1e-6)
	assert_eq(v10["count"], 10)
	assert_false(bool(v10["affordable"]), "159.37 > 100 starting money")
	# BUY_MAX with 100 money at growth 1.1: 7 levels cost 94.87, 8 would cost 114.36.
	var vmax: Dictionary = e.get_upgrade_view(0, "speed", SimTypes.BUY_MAX)
	assert_eq(vmax["count"], 7)
	assert_near(vmax["cost"].to_float(), _manual_bulk(10.0, 1.10, 0, 7), 1e-6)
	assert_true(bool(vmax["affordable"]))
	assert_true(vmax["cost"].to_float() <= 100.0)
	# Unknown upgrade/station is a safe empty view.
	assert_eq(int(e.get_upgrade_view(0, "nope", 1)["count"]), 0)
	assert_eq(int(e.get_upgrade_view(9, "speed", 1)["count"]), 0)


func test_buy_upgrade_applies_and_charges() -> void:
	var e = _engine()
	e.drain_events()
	assert_true(e.buy_upgrade(0, "speed", 1))
	assert_near(e.money.to_float(), 90.0, 1e-9)
	assert_eq(int(e.get_station_view(0)["upgrade_levels"]["speed"]), 1)
	assert_near(float(e.get_station_view(0)["stats"]["cycle_time"]), 0.9, 1e-9)
	assert_near(float(e.get_station_view(0)["throughput"]), 1.0 / 0.9, 1e-9)
	var events: Array = e.drain_events()
	var upgraded: Array = []
	var spent: Array = []
	for ev in events:
		if str(ev["t"]) == "station_upgraded":
			upgraded.append(ev)
		elif str(ev["t"]) == "money_spent":
			spent.append(ev)
	assert_eq(upgraded.size(), 1)
	assert_eq(int(upgraded[0]["station"]), 0)
	assert_eq(str(upgraded[0]["upgrade_id"]), "speed")
	assert_eq(int(upgraded[0]["levels"]), 1)
	assert_eq(int(upgraded[0]["new_level"]), 1)
	assert_eq(spent.size(), 1)
	assert_eq(str(spent[0]["context"]), "upgrade")
	assert_near(spent[0]["amount"].to_float(), 10.0, 1e-9)
	assert_eq(e.upgrade_purchase_count, 1)


func test_buy_multiplier_all_or_nothing() -> void:
	var e = _engine()
	# x10 speed costs 159.37 with only 100 money: refuse, change nothing.
	assert_false(e.buy_upgrade(0, "speed", 10))
	assert_near(e.money.to_float(), 100.0, 1e-9, "no partial purchase")
	assert_eq(int(e.get_station_view(0)["upgrade_levels"]["speed"]), 0)
	# x10 within budget succeeds and charges the exact closed-form sum.
	e.money = BigNum.from_float(1000.0)
	assert_true(e.buy_upgrade(0, "speed", 10))
	assert_near(e.money.to_float(), 1000.0 - _manual_bulk(10.0, 1.10, 0, 10), 1e-6)
	assert_eq(int(e.get_station_view(0)["upgrade_levels"]["speed"]), 10)


func test_buy_max_via_engine() -> void:
	var e = _engine()
	var exact = UpgradeMath.bulk_cost(10.0, 1.10, 0, 4)
	e.money = exact.clone()
	assert_true(e.buy_upgrade(0, "speed", SimTypes.BUY_MAX))
	assert_eq(int(e.get_station_view(0)["upgrade_levels"]["speed"]), 4, "max-buy took 4 levels")
	assert_true(e.money.to_float() < 1e-6, "spent everything to the cent")
	assert_false(e.buy_upgrade(0, "speed", SimTypes.BUY_MAX), "broke: BUY_MAX refuses")


func test_max_level_clamps() -> void:
	var e = _engine()
	e.money = BigNum.from_float(1e9)
	# machine has max_level 4; x100 clamps to the 4 available.
	assert_true(e.buy_upgrade(0, "machine", 100))
	assert_eq(int(e.get_station_view(0)["upgrade_levels"]["machine"]), 4)
	assert_near(float(e.get_station_view(0)["stats"]["capacity"]), 5.0, 1e-9, "cap 1 + 4")
	var v: Dictionary = e.get_upgrade_view(0, "machine", 1)
	assert_true(bool(v["maxed"]))
	assert_eq(int(v["count"]), 0)
	assert_false(e.buy_upgrade(0, "machine", 1), "maxed upgrade refuses")
	# BUY_MAX also respects the cap.
	assert_true(e.buy_upgrade(1, "machine", SimTypes.BUY_MAX))
	assert_eq(int(e.get_station_view(1)["upgrade_levels"]["machine"]), 4)


func test_upgrade_cost_mult_skill() -> void:
	var e = _engine()
	e.kp = 5.0
	assert_true(e.buy_skill("s_cost"))
	var v: Dictionary = e.get_upgrade_view(0, "speed", 1)
	assert_near(v["cost"].to_float(), 5.0, 1e-9, "upgrade_cost_mult 0.5 halves prices")
	var v10: Dictionary = e.get_upgrade_view(0, "speed", 10)
	assert_near(v10["cost"].to_float(), _manual_bulk(5.0, 1.10, 0, 10), 1e-6)
	assert_true(e.buy_upgrade(0, "speed", 1))
	assert_near(e.money.to_float(), 95.0, 1e-9)


func test_costs_accept_bignum_dict_form() -> void:
	# The data loader normalizes base_cost/unlock_cost to {"m","e"} dicts — the engine
	# must price identically for both encodings.
	var db: Dictionary = Autoplayer.fixture_db()
	db["stations"][0]["upgrades"]["speed"]["base_cost"] = {"m": 1.0, "e": 1}	# = 10
	db["stations"][3]["unlock_cost"] = {"m": 5.0, "e": 1}	# = 50
	var e = _engine(db)
	var v: Dictionary = e.get_upgrade_view(0, "speed", 1)
	assert_near(v["cost"].to_float(), 10.0, 1e-9, "dict base_cost prices like the number 10")
	assert_true(e.buy_upgrade(0, "speed", 1))
	assert_near(e.money.to_float(), 90.0, 1e-9)
	assert_near(e.get_station_view(3)["unlock_cost"].to_float(), 50.0, 1e-9)
	assert_true(e.unlock_station(3), "dict unlock_cost spends like the number 50")
	assert_near(e.money.to_float(), 40.0, 1e-9)


func test_locked_station_upgrades_rejected() -> void:
	var e = _engine()
	assert_false(e.buy_upgrade(3, "speed", 1), "cannot upgrade a locked station")
	assert_false(e.buy_upgrade(-1, "speed", 1))


func test_helps_bottleneck_flag() -> void:
	var e = _engine()
	# beta (index 1) is the bottleneck; its speed upgrade raises line throughput.
	assert_true(bool(e.get_upgrade_view(1, "speed", 1)["helps_bottleneck"]))
	assert_false(bool(e.get_upgrade_view(0, "speed", 1)["helps_bottleneck"]),
			"non-bottleneck station upgrades are not flagged")
	# smed on beta changes nothing (changeover already 0) -> no help.
	assert_false(bool(e.get_upgrade_view(1, "smed", 1)["helps_bottleneck"]))
	# tooling on beta raises quality -> helps.
	assert_true(bool(e.get_upgrade_view(1, "tooling", 1)["helps_bottleneck"]))


func test_effect_ops_apply_per_level() -> void:
	var e = _engine()
	e.money = BigNum.from_float(1e9)
	assert_true(e.buy_upgrade(0, "speed", 2))
	assert_near(float(e.get_station_view(0)["stats"]["cycle_time"]), pow(0.9, 2.0), 1e-9,
			"mul op compounds per level")
	assert_true(e.buy_upgrade(1, "tooling", 1))
	assert_near(float(e.get_station_view(1)["stats"]["quality"]), 0.9, 1e-9,
			"toward_one: 0.8 + 0.2*0.5")
	assert_true(e.buy_upgrade(1, "tooling", 1))
	assert_near(float(e.get_station_view(1)["stats"]["quality"]), 0.95, 1e-9,
			"toward_one compounds asymptotically")
	var db: Dictionary = Autoplayer.fixture_db()
	db["stations"][0]["base"]["changeover_time"] = 80.0
	var e2 = _engine(db)
	e2.money = BigNum.from_float(1e9)
	assert_true(e2.buy_upgrade(0, "smed", 2))
	assert_near(float(e2.get_station_view(0)["stats"]["changeover_time"]), 20.0, 1e-9,
			"smed halves changeover per level")
	assert_near(float(e2.get_station_view(0)["throughput"]), 1.0 * (1.0 - 20.0 / 600.0), 1e-9)
