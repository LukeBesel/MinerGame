## Tests for src/save/settings_service.gd — pure default/clamp/serialize helpers only.
## Hermetic: does not touch user://settings.json or the SettingsService autoload's scene-tree
## state (Timer, AudioServer bus application) -- see docs/ARCHITECTURE.md §2 gotcha 4 and §13.
extends "res://tests/test_framework.gd"

const SettingsService = preload("res://src/save/settings_service.gd")


func test_defaults_match_pinned_values() -> void:
	var d: Dictionary = SettingsService.default_settings()
	assert_near(float(d["master_volume"]), 0.8, 1e-9)
	assert_near(float(d["music_volume"]), 0.6, 1e-9)
	assert_near(float(d["sfx_volume"]), 0.8, 1e-9)
	assert_eq(d["reduce_motion"], false)
	assert_near(float(d["screen_shake"]), 0.3, 1e-9)
	assert_eq(d["number_format"], "suffix")
	assert_near(float(d["camera_sensitivity"]), 1.0, 1e-9)


func test_clamp_field_volumes_clamp_to_0_1() -> void:
	assert_near(float(SettingsService.clamp_field("master_volume", 5.0)), 1.0, 1e-9)
	assert_near(float(SettingsService.clamp_field("master_volume", -5.0)), 0.0, 1e-9)
	assert_near(float(SettingsService.clamp_field("music_volume", 0.42)), 0.42, 1e-9)
	assert_near(float(SettingsService.clamp_field("sfx_volume", 1.0)), 1.0, 1e-9)


func test_clamp_field_screen_shake_and_camera_sensitivity() -> void:
	assert_near(float(SettingsService.clamp_field("screen_shake", -1.0)), 0.0, 1e-9)
	assert_near(float(SettingsService.clamp_field("screen_shake", 2.0)), 1.0, 1e-9)
	assert_true(float(SettingsService.clamp_field("camera_sensitivity", 100.0)) < 100.0, "camera sensitivity must clamp to a sane max")
	assert_true(float(SettingsService.clamp_field("camera_sensitivity", -5.0)) > 0.0, "camera sensitivity must clamp to a positive min")


func test_clamp_field_rejects_bad_types_with_per_field_fallback() -> void:
	assert_near(float(SettingsService.clamp_field("master_volume", "loud")), 0.8, 1e-9, "non-numeric master volume falls back to ITS default, not 0")
	assert_near(float(SettingsService.clamp_field("sfx_volume", NAN)), 0.8, 1e-9, "NaN volume falls back to its default")
	assert_near(float(SettingsService.clamp_field("music_volume", INF)), 0.6, 1e-9, "Inf volume falls back to its default")
	assert_eq(SettingsService.clamp_field("reduce_motion", "yes"), false, "non-bool reduce_motion falls back to default")
	assert_eq(SettingsService.clamp_field("number_format", "hex"), "suffix", "unrecognized number_format falls back to default")
	assert_eq(SettingsService.clamp_field("number_format", "scientific"), "scientific", "recognized values pass through unchanged")


func test_sanitize_dict_fills_missing_and_clamps_present() -> void:
	var out: Dictionary = SettingsService.sanitize_dict({"master_volume": 3.0, "number_format": "scientific"})
	assert_near(float(out["master_volume"]), 1.0, 1e-9, "out-of-range values get clamped, not rejected wholesale")
	assert_eq(out["number_format"], "scientific")
	assert_near(float(out["music_volume"]), 0.6, 1e-9, "missing keys fall back to defaults")
	assert_eq(out["reduce_motion"], false)


func test_sanitize_dict_tolerant_of_garbage_input() -> void:
	assert_eq(SettingsService.sanitize_dict(null), SettingsService.default_settings(), "null -> defaults")
	assert_eq(SettingsService.sanitize_dict("not a dict"), SettingsService.default_settings(), "wrong type -> defaults")
	assert_eq(SettingsService.sanitize_dict([1, 2, 3]), SettingsService.default_settings(), "array -> defaults")
	assert_eq(SettingsService.sanitize_dict({}), SettingsService.default_settings(), "empty dict -> defaults")


func test_parse_settings_json_handles_corrupt_and_empty() -> void:
	assert_eq(SettingsService.parse_settings_json(""), SettingsService.default_settings())
	assert_eq(SettingsService.parse_settings_json("{not valid json"), SettingsService.default_settings())
	assert_eq(SettingsService.parse_settings_json("[1,2,3]"), SettingsService.default_settings())


func test_json_roundtrip_preserves_values() -> void:
	var original: Dictionary = SettingsService.default_settings()
	original["master_volume"] = 0.25
	original["reduce_motion"] = true
	original["number_format"] = "scientific"
	original["camera_sensitivity"] = 1.75

	var text: String = SettingsService.to_json_string(original)
	var parsed: Dictionary = SettingsService.parse_settings_json(text)

	assert_near(float(parsed["master_volume"]), 0.25, 1e-6)
	assert_eq(parsed["reduce_motion"], true)
	assert_eq(parsed["number_format"], "scientific")
	assert_near(float(parsed["camera_sensitivity"]), 1.75, 1e-6)
	assert_near(float(parsed["music_volume"]), 0.6, 1e-6, "untouched fields roundtrip too")


func test_to_json_string_is_valid_json() -> void:
	var text: String = SettingsService.to_json_string(SettingsService.default_settings())
	var parsed: Variant = JSON.parse_string(text)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "to_json_string must produce parseable JSON")
