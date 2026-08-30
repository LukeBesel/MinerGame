## SettingsService — user-adjustable settings persisted to user://settings.json.
## Autoload (see docs/ARCHITECTURE.md §9). Pure default/clamp/serialize helpers are static
## funcs so tests/test_settings.gd can exercise them with no disk or scene-tree dependency.
extends Node

const SETTINGS_PATH := "user://settings.json"
const SAVE_DEBOUNCE_SEC := 0.5

const CAMERA_SENS_MIN := 0.1
const CAMERA_SENS_MAX := 3.0

const NUMBER_FORMATS := ["suffix", "scientific"]

const UI_MODES := ["simple", "advanced"]

## Maps a settings key to the AudioServer bus it drives. "Master" always exists; "Music"/"SFX"
## are created by the juice agent's AudioDirector, which boots *after* this autoload (see the
## autoload order in ARCHITECTURE.md §3) — _apply_volume() guards a missing bus (index -1), and
## AudioDirector should call apply_all_volumes() once its buses exist. See INTEGRATION_NOTES.md.
const BUS_NAMES := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
}

var master_volume: float = 0.8:
	set(value):
		master_volume = float(clamp_field("master_volume", value))
		_on_field_set("master_volume", master_volume)

var music_volume: float = 0.6:
	set(value):
		music_volume = float(clamp_field("music_volume", value))
		_on_field_set("music_volume", music_volume)

var sfx_volume: float = 0.8:
	set(value):
		sfx_volume = float(clamp_field("sfx_volume", value))
		_on_field_set("sfx_volume", sfx_volume)

var reduce_motion: bool = false:
	set(value):
		reduce_motion = bool(clamp_field("reduce_motion", value))
		_on_field_set("reduce_motion", reduce_motion)

var screen_shake: float = 0.3:
	set(value):
		screen_shake = float(clamp_field("screen_shake", value))
		_on_field_set("screen_shake", screen_shake)

var number_format: String = "suffix":
	set(value):
		number_format = String(clamp_field("number_format", value))
		_on_field_set("number_format", number_format)

var camera_sensitivity: float = 1.0:
	set(value):
		camera_sensitivity = float(clamp_field("camera_sensitivity", value))
		_on_field_set("camera_sensitivity", camera_sensitivity)

var ui_mode: String = "simple":
	set(value):
		ui_mode = String(clamp_field("ui_mode", value))
		_on_field_set("ui_mode", ui_mode)

var onboarding_done: bool = false:
	set(value):
		onboarding_done = bool(clamp_field("onboarding_done", value))
		_on_field_set("onboarding_done", onboarding_done)

var _loading := false
var _save_timer: Timer


func _ready() -> void:
	_loading = true
	_apply_dict(load_dict_from_disk())
	_loading = false
	_save_timer = Timer.new()
	_save_timer.name = "SettingsSaveDebounceTimer"
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SEC
	_save_timer.timeout.connect(_flush_save)
	add_child(_save_timer)


## Generic setter used by UI/other systems that key off a String rather than the property
## directly (both paths converge on the same clamp/signal/debounced-save pipeline below).
func set_setting(key: String, value: Variant) -> void:
	match key:
		"master_volume": master_volume = value
		"music_volume": music_volume = value
		"sfx_volume": sfx_volume = value
		"reduce_motion": reduce_motion = value
		"screen_shake": screen_shake = value
		"number_format": number_format = value
		"camera_sensitivity": camera_sensitivity = value
		"ui_mode": ui_mode = value
		"onboarding_done": onboarding_done = value
		_: push_warning("SettingsService.set_setting: unknown key '%s'" % key)


func current_dict() -> Dictionary:
	return {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"reduce_motion": reduce_motion,
		"screen_shake": screen_shake,
		"number_format": number_format,
		"camera_sensitivity": camera_sensitivity,
		"ui_mode": ui_mode,
		"onboarding_done": onboarding_done,
	}


## Re-applies all three volumes to their AudioServer buses. Public so AudioDirector can call it
## once it finishes creating the Music/SFX buses (see BUS_NAMES doc comment above).
func apply_all_volumes() -> void:
	for key: String in BUS_NAMES:
		_apply_volume(BUS_NAMES[key], float(get(key)))


## Flushes any pending debounced save immediately. Called by SaveManager on quit so a setting
## changed in the last <0.5s before close isn't lost.
func force_save() -> void:
	if _save_timer != null:
		_save_timer.stop()
	_flush_save()


func load_dict_from_disk() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return default_settings()
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return default_settings()
	var text := f.get_as_text()
	f.close()
	return parse_settings_json(text)


func _apply_dict(d: Dictionary) -> void:
	master_volume = d.get("master_volume", 0.8)
	music_volume = d.get("music_volume", 0.6)
	sfx_volume = d.get("sfx_volume", 0.8)
	reduce_motion = d.get("reduce_motion", false)
	screen_shake = d.get("screen_shake", 0.3)
	number_format = d.get("number_format", "suffix")
	camera_sensitivity = d.get("camera_sensitivity", 1.0)
	ui_mode = d.get("ui_mode", "simple")
	onboarding_done = d.get("onboarding_done", false)


func _on_field_set(key: String, value: Variant) -> void:
	if BUS_NAMES.has(key):
		_apply_volume(BUS_NAMES[key], float(value))
	if _loading:
		return
	EventBus.settings_changed.emit(key, value)
	_schedule_save()


func _apply_volume(bus_name: String, linear_value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear_value, 0.0, 1.0)))


func _schedule_save() -> void:
	if _save_timer == null:
		return
	_save_timer.start(SAVE_DEBOUNCE_SEC)


func _flush_save() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SettingsService: failed to write %s (err=%d)" % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	f.store_string(to_json_string(current_dict()))
	f.close()


# ---------------------------------------------------------------------------
# Pure helpers — static, no autoloads/disk/tree. Covered directly by tests/test_settings.gd.
# ---------------------------------------------------------------------------

static func default_settings() -> Dictionary:
	return {
		"master_volume": 0.8,
		"music_volume": 0.6,
		"sfx_volume": 0.8,
		"reduce_motion": false,
		"screen_shake": 0.3,
		"number_format": "suffix",
		"camera_sensitivity": 1.0,
		"ui_mode": "simple",
		"onboarding_done": false,
	}


## Clamps/coerces a single field's value into its valid range/type, falling back to that
## field's default on bad input (missing, wrong type, NaN/Inf, out of range, unrecognized enum).
static func clamp_field(key: String, value: Variant) -> Variant:
	var fallback: Variant = default_settings().get(key, value)
	match key:
		"master_volume", "music_volume", "sfx_volume", "screen_shake":
			return clampf(_as_float(value, float(fallback)), 0.0, 1.0)
		"camera_sensitivity":
			return clampf(_as_float(value, float(fallback)), CAMERA_SENS_MIN, CAMERA_SENS_MAX)
		"reduce_motion", "onboarding_done":
			return value if typeof(value) == TYPE_BOOL else fallback
		"number_format":
			if typeof(value) == TYPE_STRING and NUMBER_FORMATS.has(value):
				return value
			return fallback
		"ui_mode":
			if typeof(value) == TYPE_STRING and UI_MODES.has(value):
				return value
			return fallback
		_:
			return value


static func _as_float(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var f := float(value)
	if is_nan(f) or is_inf(f):
		return fallback
	return f


## Merges arbitrary parsed JSON (Variant — may be null/wrong-typed/partial) onto defaults,
## clamping every recognized field. Never throws; always returns a complete, valid dict.
static func sanitize_dict(raw: Variant) -> Dictionary:
	var out := default_settings()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key: String in out.keys():
		if raw.has(key):
			out[key] = clamp_field(key, raw[key])
	return out


## Parses a settings JSON string. Returns defaults for empty/corrupt/non-object input.
static func parse_settings_json(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return default_settings()
	var parsed: Variant = JSON.parse_string(text)
	return sanitize_dict(parsed)


static func to_json_string(d: Dictionary) -> String:
	return JSON.stringify(sanitize_dict(d), "\t")
