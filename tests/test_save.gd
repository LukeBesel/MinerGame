## Tests for src/save/save_manager.gd — pure validation/migration/codec/rotation logic only.
## Hermetic: no Game/sim dependency, no autoload access, no user:// disk I/O (see
## docs/ARCHITECTURE.md §2 gotcha 4 and §13). Synthetic save docs are plain dicts.
extends "res://tests/test_framework.gd"

const SaveManager = preload("res://src/save/save_manager.gd")


func _doc(version: int = 1, saved_at: int = 1000) -> Dictionary:
	return {
		"version": version,
		"saved_at_unix": saved_at,
		"app": "bottleneck",
		"sim": {"lifetime_parts": {"m": 1.0, "e": 2}},
	}


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func test_validate_accepts_well_formed_doc() -> void:
	var doc := _doc()
	assert_true(SaveManager.is_valid_doc(doc, 2000), "well-formed doc should validate")
	assert_eq(SaveManager.validate_reason(doc, 2000), "")


func test_validate_rejects_non_dictionary() -> void:
	assert_false(SaveManager.is_valid_doc(null), "null is not a doc")
	assert_false(SaveManager.is_valid_doc("not a doc"), "a bare string is not a doc")
	assert_false(SaveManager.is_valid_doc([1, 2, 3]), "a JSON array is not a doc")
	assert_false(SaveManager.is_valid_doc(42), "a bare number is not a doc")


func test_validate_rejects_bad_version() -> void:
	assert_false(SaveManager.is_valid_doc(_doc(0, 1000), 2000), "version 0 is out of range")
	assert_false(SaveManager.is_valid_doc(_doc(2, 1000), 2000), "version above SAVE_VERSION")
	var missing := _doc()
	missing.erase("version")
	assert_false(SaveManager.is_valid_doc(missing, 2000), "missing version")
	var bad_type := _doc()
	bad_type["version"] = "one"
	assert_false(SaveManager.is_valid_doc(bad_type, 2000), "non-numeric version")


func test_validate_rejects_bad_saved_at() -> void:
	assert_false(SaveManager.is_valid_doc(_doc(1, 0), 2000), "saved_at_unix zero")
	assert_false(SaveManager.is_valid_doc(_doc(1, -5), 2000), "saved_at_unix negative")
	assert_false(SaveManager.is_valid_doc(_doc(1, 2000 + 86400 + 10), 2000), "too far in the future")
	assert_true(SaveManager.is_valid_doc(_doc(1, 2000 + 86400 - 10), 2000), "just inside the 1-day future slack")


func test_validate_rejects_bad_sim() -> void:
	var d := _doc()
	d["sim"] = "not a dict"
	assert_false(SaveManager.is_valid_doc(d, 2000), "sim must be a dictionary")
	d.erase("sim")
	assert_false(SaveManager.is_valid_doc(d, 2000), "sim must be present")


func test_parse_and_validate_handles_corrupt_json() -> void:
	var r1: Dictionary = SaveManager.parse_and_validate("{not valid json", 2000)
	assert_false(r1["ok"], "syntactically broken JSON should not validate")
	assert_eq(r1["doc"], {})

	var r2: Dictionary = SaveManager.parse_and_validate("", 2000)
	assert_false(r2["ok"], "empty string is not a valid doc")

	var r3: Dictionary = SaveManager.parse_and_validate("[1, 2, 3]", 2000)
	assert_false(r3["ok"], "a JSON array is not a save doc")

	var text := JSON.stringify(_doc(1, 1500))
	var r4: Dictionary = SaveManager.parse_and_validate(text, 2000)
	assert_true(r4["ok"], "well-formed JSON should validate")
	assert_eq(int(r4["doc"]["saved_at_unix"]), 1500)


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

func test_migrate_noop_when_already_current() -> void:
	var doc := _doc(SaveManager.SAVE_VERSION, 1000)
	var out: Dictionary = SaveManager._migrate(doc)
	assert_eq(int(out["version"]), SaveManager.SAVE_VERSION)
	assert_eq(out["sim"], doc["sim"])


func test_migrate_v0_to_v1_stamps_version_and_preserves_data() -> void:
	var doc := {"version": 0, "saved_at_unix": 1000, "app": "bottleneck", "sim": {"lifetime_parts": {"m": 5.0, "e": 1}}}
	var out: Dictionary = SaveManager._migrate(doc)
	assert_eq(int(out["version"]), SaveManager.SAVE_VERSION, "migration should land exactly on SAVE_VERSION")
	assert_eq(out["app"], "bottleneck", "unrelated fields pass through untouched")
	assert_eq(out["sim"], doc["sim"])
	assert_eq(int(doc["version"]), 0, "migrate must not mutate its input")


func test_migrate_stops_gracefully_when_no_step_registered() -> void:
	var doc := {"version": -5, "saved_at_unix": 1000, "app": "bottleneck", "sim": {}}
	var out: Dictionary = SaveManager._migrate(doc)
	assert_eq(int(out["version"]), -5, "with no registered step, migrate leaves the doc as-is instead of looping forever")


func test_migrations_registry_has_a_step_for_every_version_below_current() -> void:
	# The stepping machinery must have a real path for every version < SAVE_VERSION -- if a future
	# SAVE_VERSION ships without a matching MIGRATIONS entry, old saves would get stuck mid-chain.
	var v := 0
	while v < SaveManager.SAVE_VERSION:
		assert_true(SaveManager.MIGRATIONS.has(v), "missing migration step from version %d" % v)
		v += 1


# ---------------------------------------------------------------------------
# Export / import string codec
# ---------------------------------------------------------------------------

func test_export_string_prefix_and_roundtrip() -> void:
	var doc := _doc(1, 4242)
	var encoded: String = SaveManager.encode_export_string(doc)
	assert_true(encoded.begins_with("BNK1."), "export string must start with the BNK1. prefix")

	var result: Dictionary = SaveManager.decode_export_string(encoded, 5000)
	assert_true(result["ok"], "a freshly encoded doc must decode+validate cleanly")
	assert_eq(int(result["doc"]["saved_at_unix"]), 4242)
	assert_eq(result["doc"]["app"], "bottleneck")


func test_import_string_rejects_bad_prefix() -> void:
	var result: Dictionary = SaveManager.decode_export_string("NOPE.xxxxx", 5000)
	assert_false(result["ok"])
	assert_eq(result["reason"], "bad prefix")


func test_import_string_rejects_garbage_after_valid_prefix() -> void:
	var result: Dictionary = SaveManager.decode_export_string("BNK1.not-valid-base64!!!", 5000)
	assert_false(result["ok"], "garbage payload after a valid prefix must still be rejected")


func test_import_string_rejects_well_formed_but_invalid_doc() -> void:
	var payload := Marshalls.utf8_to_base64(JSON.stringify({"nope": true}))
	var result: Dictionary = SaveManager.decode_export_string("BNK1." + payload, 5000)
	assert_false(result["ok"], "well-formed base64/JSON that isn't a valid save doc must be rejected")


# ---------------------------------------------------------------------------
# Rotation planning
# ---------------------------------------------------------------------------

func test_rotation_plan_order_and_paths() -> void:
	var plan: Array = SaveManager.rotation_plan("user://saves/")
	assert_eq(plan.size(), 2, "exactly two shift operations for a 3-slot rotation")
	assert_eq(plan[0]["from"], "user://saves/save_1.json")
	assert_eq(plan[0]["to"], "user://saves/save_2.json")
	assert_eq(plan[1]["from"], "user://saves/save_0.json")
	assert_eq(plan[1]["to"], "user://saves/save_1.json")


# ---------------------------------------------------------------------------
# build_save_doc
# ---------------------------------------------------------------------------

func test_build_save_doc_shape() -> void:
	var doc: Dictionary = SaveManager.build_save_doc({"foo": 1}, 9999)
	assert_eq(int(doc["version"]), SaveManager.SAVE_VERSION)
	assert_eq(int(doc["saved_at_unix"]), 9999)
	assert_eq(doc["app"], "bottleneck")
	assert_eq(doc["sim"], {"foo": 1})
	assert_true(SaveManager.is_valid_doc(doc, 9999 + 10))


# ---------------------------------------------------------------------------
# Steam cloud-conflict decision (src/steam/steam_bridge.gd — pure/static, tested here alongside
# the rest of the save-doc-shaped decision logic; steam_bridge has no other testable surface).
# ---------------------------------------------------------------------------

func test_cloud_conflict_agrees_when_newer_is_also_more_progressed() -> void:
	var SteamBridgeScript = preload("res://src/steam/steam_bridge.gd")
	var local := {"saved_at_unix": 2000, "lifetime_parts": 500.0}
	var cloud := {"saved_at_unix": 1000, "lifetime_parts": 100.0}
	assert_eq(SteamBridgeScript.resolve_cloud_conflict(local, cloud), "local")
	assert_eq(SteamBridgeScript.resolve_cloud_conflict(cloud, local), "cloud")


func test_cloud_conflict_asks_when_older_save_has_more_progress() -> void:
	var SteamBridgeScript = preload("res://src/steam/steam_bridge.gd")
	# Newer by time, but far LESS lifetime progress than the older save -- looks like a second
	# machine with real unsynced progress, or a rollback. Must not be resolved silently.
	var local := {"saved_at_unix": 2000, "lifetime_parts": 10.0}
	var cloud := {"saved_at_unix": 1000, "lifetime_parts": 5000.0}
	assert_eq(SteamBridgeScript.resolve_cloud_conflict(local, cloud), "ask")


func test_cloud_conflict_handles_missing_sides() -> void:
	var SteamBridgeScript = preload("res://src/steam/steam_bridge.gd")
	assert_eq(SteamBridgeScript.resolve_cloud_conflict({}, {}), "local", "nothing on either side is a degenerate no-op")
	var local := {"saved_at_unix": 1000, "lifetime_parts": 5.0}
	assert_eq(SteamBridgeScript.resolve_cloud_conflict(local, {}), "local", "no cloud save yet -> local wins")
	assert_eq(SteamBridgeScript.resolve_cloud_conflict({}, local), "cloud", "no local save yet -> cloud wins")
