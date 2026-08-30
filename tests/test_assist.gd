## Tests for the assist backend (FIX IT): best_bottleneck_fix scoring (delta rps/cost),
## affordability fallback, max_level and unlock handling (value-add pricing), and
## apply_best_fix buying exactly one level. Also covers the granted settings exception
## (ui_mode / onboarding_done — the simple-mode/onboarding backend this assist API serves).
extends "res://tests/test_framework.gd"

const Autoplayer = preload("res://tests/autoplayer.gd")
const SimEngineScript = preload("res://src/sim/sim_engine.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const BigNum = preload("res://src/sim/big_num.gd")
const Loader = preload("res://src/data/loader.gd")

# settings_service.gd references autoloads, so it is runtime-load()ed inside its test
# (keeps this file clean under plain --check-only; same pattern as test_pacing's loader).
const SETTINGS_PATH := "res://src/save/settings_service.gd"


func _engine(db: Dictionary = {}):
	if db.is_empty():
		db = Autoplayer.fixture_db()
	return SimEngineScript.new_game(db)


## Fixture scores on beta (the 0.4 pps bottleneck), price 1.0 flat, money 100:
## machine +0.400 pps / $25 = .0160 | speed +0.044 / $10 = .0044 | tooling +0.050 / $15
## = .0033 | smed +0 (excluded) | unlock delta +0 rps flat-priced (excluded).
func test_picks_highest_delta_rps_per_cost() -> void:
	var e = _engine()
	var fix: Dictionary = e.best_bottleneck_fix()
	assert_false(fix.is_empty(), "a fix exists for the fixture bottleneck")
	assert_eq(str(fix["kind"]), "upgrade")
	assert_eq(int(fix["station"]), 1, "targets the bottleneck station")
	assert_eq(str(fix["upgrade_id"]), "machine", "machine has the best delta rps per cost")
	assert_near(fix["cost"].to_float(), 25.0, 1e-9, "single-level cost at level 0")
	assert_true(bool(fix["affordable"]), "money 100 covers the $25 machine")
	assert_true(float(fix["delta_rps"]) > 0.39, "additive delta_rps carried for the UI")
	for key in ["kind", "station", "upgrade_id", "cost", "affordable"]:
		assert_true(fix.has(key), "pinned fix key %s" % key)


func test_respects_affordability_with_save_up_fallback() -> void:
	var e = _engine()
	# $20: machine ($25) out of reach — best AFFORDABLE is speed (.0044 beats tooling .0033).
	e.money = BigNum.from_float(20.0)
	var fix: Dictionary = e.best_bottleneck_fix()
	assert_eq(str(fix["upgrade_id"]), "speed", "best affordable move wins when the top pick is too dear")
	assert_true(bool(fix["affordable"]))
	# $5: nothing affordable — return the best move anyway, flagged for the save-up label.
	e.money = BigNum.from_float(5.0)
	fix = e.best_bottleneck_fix()
	assert_eq(str(fix["upgrade_id"]), "machine", "best overall move still reported")
	assert_false(bool(fix["affordable"]), "flagged unaffordable so the UI shows 'save up'")
	assert_near(fix["cost"].to_float(), 25.0, 1e-9, "cost tells the player the target")


func test_max_level_track_excluded() -> void:
	var db: Dictionary = Autoplayer.fixture_db()
	db["stations"][1]["upgrades"]["machine"]["max_level"] = 1
	var e = _engine(db)
	assert_true(e.buy_upgrade(1, "machine", 1))	# beta tp 0.4 -> 0.8, still the bottleneck
	assert_eq(e.bottleneck, 1)
	var fix: Dictionary = e.best_bottleneck_fix()
	assert_false(fix.is_empty())
	assert_false(str(fix["upgrade_id"]) == "machine", "maxed track never proposed")
	# speed now moves beta but not the LINE (alpha suffix-bound at 0.8): tooling is the
	# only move that raises steady rps, so the assist must see through to it.
	assert_eq(str(fix["upgrade_id"]), "tooling", "scores line delta, not station delta")


func test_unlock_chosen_when_genuinely_better_under_value_add() -> void:
	var db: Dictionary = Autoplayer.fixture_db()
	db["balance"]["value_add_pricing"] = true
	db["stations"][3]["unlock_cost"] = 5
	# Unlock: steady 0.4 stays (delta is fast, q 1) but price 3 -> 4: +0.4 rps / $5 = .080
	# beats machine (+0.4 pps x $3 price = +1.2 rps / $25 = .048).
	var e = _engine(db)
	var fix: Dictionary = e.best_bottleneck_fix()
	assert_eq(str(fix["kind"]), "unlock", "line extension wins on delta rps per cost")
	assert_eq(int(fix["station"]), 3)
	assert_eq(str(fix["upgrade_id"]), "", "no upgrade id on an unlock move")
	assert_near(fix["cost"].to_float(), 5.0, 1e-9)
	assert_true(bool(fix["affordable"]))
	assert_true(e.apply_best_fix(), "unlock executes")
	assert_true(bool(e.get_station_view(3)["unlocked"]))
	# At the real fixture price ($50) the same unlock scores .008 and machine wins again.
	var db2: Dictionary = Autoplayer.fixture_db()
	db2["balance"]["value_add_pricing"] = true
	var e2 = _engine(db2)
	var fix2: Dictionary = e2.best_bottleneck_fix()
	assert_eq(str(fix2["kind"]), "upgrade", "pricey unlock loses the scoring fairly")
	assert_eq(str(fix2["upgrade_id"]), "machine")


func test_apply_buys_exactly_one_level() -> void:
	var e = _engine()
	assert_true(e.apply_best_fix())
	assert_eq(int(e.get_station_view(1)["upgrade_levels"]["machine"]), 1, "one machine level")
	assert_near(e.money.to_float(), 75.0, 1e-9, "charged for exactly one level")
	assert_eq(e.upgrade_purchase_count, 1)
	# Next call re-evaluates: machine +1 no longer moves the line (alpha-bound), tooling does.
	assert_true(e.apply_best_fix())
	assert_eq(int(e.get_station_view(1)["upgrade_levels"]["tooling"]), 1)
	assert_eq(int(e.get_station_view(1)["upgrade_levels"]["machine"]), 1, "machine untouched")
	assert_near(e.money.to_float(), 60.0, 1e-9)
	assert_eq(e.upgrade_purchase_count, 2)
	# Unaffordable fix is never force-bought.
	e.money = BigNum.from_float(0.5)
	assert_false(e.apply_best_fix(), "apply refuses when the fix is not affordable")
	assert_eq(e.upgrade_purchase_count, 2, "nothing bought")


func test_empty_when_no_bottleneck_or_no_useful_move() -> void:
	# Fully locked line: no bottleneck yet.
	var db: Dictionary = Autoplayer.fixture_db()
	for s_v in db["stations"]:
		(s_v as Dictionary)["unlock_cost"] = 10
	var e = _engine(db)
	assert_eq(e.bottleneck, -1)
	assert_true(e.best_bottleneck_fix().is_empty(), "{} when there is no bottleneck")
	assert_false(e.apply_best_fix())
	# Single fully-maxed station, nothing left to unlock: no useful move.
	var db2: Dictionary = Autoplayer.fixture_db()
	db2["stations"] = [db2["stations"][0]]
	for uid in ["speed", "machine", "tooling", "smed"]:
		db2["stations"][0]["upgrades"][uid]["max_level"] = 1
	var e2 = _engine(db2)
	e2.money = BigNum.from_float(1e6)
	for uid in ["speed", "machine", "tooling", "smed"]:
		assert_true(e2.buy_upgrade(0, uid, 1))
	assert_true(e2.best_bottleneck_fix().is_empty(), "{} when every track is maxed and no unlock remains")


func test_fix_on_real_data_boot() -> void:
	# Real data (when present): lathe opens as the bottleneck and its first fix is
	# affordable with starting money — the FIX IT button works from the first click.
	if not FileAccess.file_exists("res://src/data/stations.json"):
		assert_true(true)
		return
	var db_v: Variant = Loader.load_all()
	var e = _engine(db_v)
	var fix: Dictionary = e.best_bottleneck_fix()
	assert_false(fix.is_empty(), "boot state offers a fix")
	assert_eq(str(fix["kind"]), "upgrade")
	assert_eq(int(fix["station"]), 1, "targets the opening lathe bottleneck")
	assert_true(bool(fix["affordable"]), "first fix affordable with starting money")
	var steady_before: float = e.estimate_steady_pps()
	assert_true(e.apply_best_fix())
	assert_true(e.estimate_steady_pps() > steady_before + 1e-9,
			"the first fix genuinely speeds the line")


func test_settings_ui_mode_and_onboarding_fields() -> void:
	# Granted exception coverage: the two settings fields backing simple mode + onboarding,
	# tested through the same pure statics test_settings.gd uses (hermetic, no autoload).
	var settings_lib: Variant = load(SETTINGS_PATH)
	var d: Dictionary = settings_lib.default_settings()
	assert_eq(d["ui_mode"], "simple", "simple mode is the default for new players")
	assert_eq(d["onboarding_done"], false)
	assert_eq(settings_lib.clamp_field("ui_mode", "advanced"), "advanced")
	assert_eq(settings_lib.clamp_field("ui_mode", "simple"), "simple")
	assert_eq(settings_lib.clamp_field("ui_mode", "expert"), "simple", "unknown mode falls back")
	assert_eq(settings_lib.clamp_field("ui_mode", 42), "simple", "non-string falls back")
	assert_eq(settings_lib.clamp_field("onboarding_done", true), true)
	assert_eq(settings_lib.clamp_field("onboarding_done", "yes"), false, "non-bool falls back")
	var text: String = settings_lib.to_json_string({"ui_mode": "advanced", "onboarding_done": true})
	var parsed: Dictionary = settings_lib.parse_settings_json(text)
	assert_eq(parsed["ui_mode"], "advanced", "roundtrips through the settings JSON")
	assert_eq(parsed["onboarding_done"], true)
	assert_eq(settings_lib.sanitize_dict(null)["ui_mode"], "simple", "garbage input -> defaults")
