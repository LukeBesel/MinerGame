## Pacing validation: runs the greedy autoplayer. Always smoke-tests the bot on the inline
## fixture; when the real data layer is present (stations.json + loader.load_all), replays
## the full game at max speed and asserts first prestige lands inside
## balance.pacing.first_prestige_target_minutes with >= 6 distinct progress events by 15 min.
extends "res://tests/test_framework.gd"

const Autoplayer = preload("res://tests/autoplayer.gd")

const STATIONS_JSON := "res://src/data/stations.json"
const LOADER_PATH := "res://src/data/loader.gd"


func test_autoplayer_smoke_on_fixture() -> void:
	var bot = Autoplayer.new()
	var result: Dictionary = bot.run(Autoplayer.fixture_db(), 900.0)
	assert_true((result["log"] as Array).size() > 0, "bot generated an event log")
	assert_true(bot.engine.upgrade_purchase_count > 0, "bot bought upgrades")
	assert_true(bot.distinct_progress_events(900.0) >= 4,
			"bot hit several distinct progress events on the fixture")
	var t: Dictionary = bot.engine.debug_totals()
	var balance_sum: float = float(t["sold"]) + float(t["scrap"]) + float(t["wip"]) + float(t["flushed"])
	assert_near(float(t["started"]), balance_sum, 1e-6 * float(t["started"]) + 1e-9,
			"conservation holds under bot play (incl. prestige-flushed WIP)")
	# The greedy bot must reach the fixture's small prestige gate (1000 parts) inside 900 s.
	assert_true(bool(result["prestiged"]), "bot prestiged on the fixture economy")
	assert_true(float(result["prestige_time"]) > 0.0)


func test_pacing_first_prestige_on_real_data() -> void:
	var db := _load_real_db()
	if db.is_empty():
		print("SKIP pacing (data not present)")
		assert_true(true)
		return
	var pacing_v: Variant = (db.get("balance", {}) as Dictionary).get("pacing", {})
	var target: Array = [25.0, 50.0]
	if typeof(pacing_v) == TYPE_DICTIONARY:
		var t_v: Variant = (pacing_v as Dictionary).get("first_prestige_target_minutes", target)
		if typeof(t_v) == TYPE_ARRAY and (t_v as Array).size() >= 2:
			target = t_v
	var lo_s: float = float(target[0]) * 60.0
	var hi_s: float = float(target[1]) * 60.0
	var bot = Autoplayer.new()
	var result: Dictionary = bot.run(db, hi_s * 1.25)
	var printed: int = 0
	for entry in bot.event_log:
		var id := str(entry[1])
		var progress := id.begins_with("prestige_performed") or id.begins_with("bottleneck_cleared")
		for prefix in Autoplayer.PROGRESS_EVENT_TYPES:
			if id.begins_with(prefix + ":"):
				progress = true
		if progress and printed < 400:
			print("AUTOPLAY t=%.1f event=%s" % [float(entry[0]), id])
			printed += 1
	var distinct: int = bot.distinct_progress_events(900.0)
	print("AUTOPLAY summary: prestige_time=%.1fs (target %.0f..%.0fs) distinct_events_15min=%d" % [
			float(result["prestige_time"]), lo_s, hi_s, distinct])
	assert_true(bool(result["prestiged"]), "bot reached first prestige on real data")
	if bool(result["prestiged"]):
		assert_true(float(result["prestige_time"]) >= lo_s,
				"first prestige not before %.0f min (got %.1f min)" % [
				float(target[0]), float(result["prestige_time"]) / 60.0])
		assert_true(float(result["prestige_time"]) <= hi_s,
				"first prestige not after %.0f min (got %.1f min)" % [
				float(target[1]), float(result["prestige_time"]) / 60.0])
	assert_true(distinct >= 6,
			"expected >= 6 distinct unlock/milestone events in first 15 min, got %d" % distinct)


## Returns the real db via Data's static loader, or {} when the data layer is not ready yet.
func _load_real_db() -> Dictionary:
	if not FileAccess.file_exists(STATIONS_JSON):
		return {}
	if not ResourceLoader.exists(LOADER_PATH):
		return {}
	var loader_script: Variant = load(LOADER_PATH)
	if loader_script == null:
		return {}
	var has_load_all := false
	for m in (loader_script as Script).get_script_method_list():
		if str(m.get("name", "")) == "load_all":
			has_load_all = true
	if not has_load_all:
		return {}
	var db_v: Variant = loader_script.load_all()
	if typeof(db_v) != TYPE_DICTIONARY:
		return {}
	var db: Dictionary = db_v
	var stations_v: Variant = db.get("stations", [])
	if typeof(stations_v) != TYPE_ARRAY or (stations_v as Array).is_empty():
		return {}
	if typeof(db.get("balance", {})) != TYPE_DICTIONARY or (db.get("balance", {}) as Dictionary).is_empty():
		return {}
	return db
