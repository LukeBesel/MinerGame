## SaveManager — autosave rotation, versioned migration, export/import strings, and the
## boot-time load + offline-progress orchestration described in docs/ARCHITECTURE.md §9.
## Autoload. Validation/migration/codec/rotation helpers are static funcs so tests/test_save.gd
## can exercise them on synthetic dicts with no dependency on Game/sim or user:// disk state.
extends Node

const SAVE_DIR := "user://saves/"
const SAVE_SLOTS := ["save_0.json", "save_1.json", "save_2.json"]
const SAVE_VERSION := 1
const EXPORT_PREFIX := "BNK1."
const APP_ID_STRING := "bottleneck"
const DEFAULT_OFFLINE_MIN_SECONDS := 60.0
const DEFAULT_AUTOSAVE_SECONDS := 30.0
const FUTURE_SLACK_SECONDS := 86400  # saved_at_unix may not be more than 1 day ahead of "now"

## MIGRATIONS[from_version] names the static step function that upgrades a doc from
## from_version to from_version+1; _migrate() below dispatches through it. Empty in spirit today
## (SAVE_VERSION==1 — every real save already validates at the current version, so nothing ever
## reaches a step in production) except one synthetic v0->v1 no-op entry, kept only so the
## stepwise machinery has a real path to exercise — see tests/test_save.gd and
## src/save/INTEGRATION_NOTES.md for how to add the next real one.
const MIGRATIONS := {
	0: "migrate_v0_to_v1",
}

var _autosave_timer: Timer


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.one_shot = false
	_autosave_timer.wait_time = _autosave_seconds()
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)
	_autosave_timer.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save("quit")
		if SettingsService.has_method("force_save"):
			SettingsService.force_save()
		get_tree().quit()


func _on_autosave_timeout() -> void:
	save("auto")


# ---------------------------------------------------------------------------
# Boot load
# ---------------------------------------------------------------------------

## Loads the newest valid save among save_0 (newest) -> save_1 -> save_2, applies it, and kicks
## off offline-progress reporting. Starts a new game (with a toast) if none of the three validate.
func boot_load() -> void:
	var saw_corrupt := false
	for fname in SAVE_SLOTS:
		var path: String = SAVE_DIR + fname
		if not FileAccess.file_exists(path):
			continue
		var result: Dictionary = parse_and_validate(_read_text(path))
		if not result["ok"]:
			push_warning("SaveManager: %s invalid (%s)" % [path, result["reason"]])
			saw_corrupt = true
			continue
		_apply_loaded_doc(result["doc"])
		return
	if Game.has_method("new_game"):
		Game.new_game()
	if saw_corrupt:
		EventBus.request_toast.emit(L.t("save.corrupt_new_game"))


func _apply_loaded_doc(raw_doc: Dictionary) -> void:
	var doc: Dictionary = _migrate(raw_doc)
	var sim_state: Variant = doc.get("sim", {})
	if typeof(sim_state) != TYPE_DICTIONARY:
		sim_state = {}
	if Game.has_method("apply_loaded_state"):
		Game.apply_loaded_state(sim_state)
	var saved_at: int = int(doc.get("saved_at_unix", 0))
	var now: int = int(Time.get_unix_time_from_system())
	var elapsed: float = float(maxi(0, now - saved_at))
	if elapsed >= _offline_min_seconds() and Game.has_method("offline_progress"):
		var report: Variant = Game.offline_progress(elapsed)
		if typeof(report) == TYPE_DICTIONARY:
			EventBus.offline_report.emit(report)


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


# ---------------------------------------------------------------------------
# Save + rotation
# ---------------------------------------------------------------------------

## Rotates backups (save_1->save_2, save_0->save_1) and writes a fresh save_0.json from
## Game.serialize(). `reason` is echoed on EventBus.save_completed/save_failed for UI toasts
## ("auto" | "manual" | "quit" | "prestige" | "import" | ...) — it is not a filesystem slot id.
func save(reason: String = "auto") -> bool:
	if not Game.has_method("serialize"):
		EventBus.save_failed.emit("game_not_ready")
		return false
	var sim_state: Variant = Game.serialize()
	if typeof(sim_state) != TYPE_DICTIONARY:
		EventBus.save_failed.emit("serialize_invalid")
		return false
	var doc: Dictionary = build_save_doc(sim_state)
	_rotate_saves()
	var ok: bool = _write_doc_to_path(doc, SAVE_DIR + SAVE_SLOTS[0])
	if ok:
		EventBus.save_completed.emit(reason)
	else:
		EventBus.save_failed.emit("write_error")
	return ok


func _rotate_saves() -> void:
	_ensure_save_dir()
	for op: Dictionary in rotation_plan(SAVE_DIR):
		var from: String = op["from"]
		var to: String = op["to"]
		if FileAccess.file_exists(from):
			DirAccess.copy_absolute(from, to)


func _ensure_save_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _write_doc_to_path(doc: Dictionary, path: String) -> bool:
	_ensure_save_dir()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open %s for write (err=%d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	return true


# ---------------------------------------------------------------------------
# Export / import
# ---------------------------------------------------------------------------

func export_string() -> String:
	var sim_state: Variant = {}
	if Game.has_method("serialize"):
		sim_state = Game.serialize()
	if typeof(sim_state) != TYPE_DICTIONARY:
		sim_state = {}
	return encode_export_string(build_save_doc(sim_state))


## Decodes, validates, applies (incl. offline calc), and persists an exported string.
## Returns false (and emits save_failed) without touching current state if it doesn't validate.
func import_string(s: String) -> bool:
	var result: Dictionary = decode_export_string(s)
	if not result["ok"]:
		EventBus.save_failed.emit("import_invalid:" + String(result["reason"]))
		return false
	_apply_loaded_doc(result["doc"])
	return save("import")


# ---------------------------------------------------------------------------
# Pure helpers — static, no autoloads/disk/tree. Covered directly by tests/test_save.gd.
# ---------------------------------------------------------------------------

static func build_save_doc(sim_state: Dictionary, now_unix: int = -1) -> Dictionary:
	var now: int = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	return {
		"version": SAVE_VERSION,
		"saved_at_unix": now,
		"app": APP_ID_STRING,
		"sim": sim_state,
	}


## "" if doc passes structural validation, else a short human-readable reason.
## now_unix lets tests pin "now" instead of racing the wall clock; -1 uses real time.
static func validate_reason(doc: Variant, now_unix: int = -1) -> String:
	if typeof(doc) != TYPE_DICTIONARY:
		return "not a dictionary"
	if not doc.has("version") or (typeof(doc["version"]) != TYPE_INT and typeof(doc["version"]) != TYPE_FLOAT):
		return "missing/invalid version"
	var version: int = int(doc["version"])
	if version < 1 or version > SAVE_VERSION:
		return "version %d out of supported range 1..%d" % [version, SAVE_VERSION]
	if not doc.has("saved_at_unix") or (typeof(doc["saved_at_unix"]) != TYPE_INT and typeof(doc["saved_at_unix"]) != TYPE_FLOAT):
		return "missing/invalid saved_at_unix"
	var saved_at: int = int(doc["saved_at_unix"])
	if saved_at <= 0:
		return "saved_at_unix not positive"
	var now: int = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if saved_at > now + FUTURE_SLACK_SECONDS:
		return "saved_at_unix too far in the future"
	if not doc.has("sim") or typeof(doc["sim"]) != TYPE_DICTIONARY:
		return "sim is not a dictionary"
	return ""


static func is_valid_doc(doc: Variant, now_unix: int = -1) -> bool:
	return validate_reason(doc, now_unix) == ""


## Parses a save-doc JSON string and validates it in one step. Never throws — a syntactically
## broken string (or any non-object JSON) just comes back not-ok. {"ok", "doc", "reason"}.
static func parse_and_validate(text: String, now_unix: int = -1) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	var reason: String = validate_reason(parsed, now_unix)
	if reason != "":
		return {"ok": false, "doc": {}, "reason": reason}
	return {"ok": true, "doc": parsed, "reason": ""}


static func encode_export_string(doc: Dictionary) -> String:
	return EXPORT_PREFIX + Marshalls.utf8_to_base64(JSON.stringify(doc))


## {"ok", "doc", "reason"} — same shape as parse_and_validate. Rejects anything not starting
## with EXPORT_PREFIX outright; anything after it flows through the normal parse+validate path
## (bad base64 decodes to a string that just fails JSON parsing, which is still a clean reject).
static func decode_export_string(s: String, now_unix: int = -1) -> Dictionary:
	if not s.begins_with(EXPORT_PREFIX):
		return {"ok": false, "doc": {}, "reason": "bad prefix"}
	var b64: String = s.substr(EXPORT_PREFIX.length())
	var json_text: String = Marshalls.base64_to_utf8(b64)
	return parse_and_validate(json_text, now_unix)


## Ordered rotation copy ops to run BEFORE writing fresh content into slot 0: oldest shift first
## (save_1->save_2, THEN save_0->save_1) so nothing is overwritten before it's been copied out.
static func rotation_plan(dir: String) -> Array:
	return [
		{"from": dir + SAVE_SLOTS[1], "to": dir + SAVE_SLOTS[2]},
		{"from": dir + SAVE_SLOTS[0], "to": dir + SAVE_SLOTS[1]},
	]


## Applies registered MIGRATIONS steps until doc.version == SAVE_VERSION (or no step is
## registered for the current version, whichever comes first). Pure: dict in, dict out — never
## mutates its argument.
static func _migrate(doc: Dictionary) -> Dictionary:
	var out: Dictionary = doc.duplicate(true)
	var guard: int = 0
	while int(out.get("version", SAVE_VERSION)) < SAVE_VERSION and guard < 64:
		var v: int = int(out.get("version", SAVE_VERSION))
		if not MIGRATIONS.has(v):
			break
		match String(MIGRATIONS[v]):
			"migrate_v0_to_v1":
				out = migrate_v0_to_v1(out)
			_:
				break
		guard += 1
	return out


## Synthetic v0->v1 step — v0 saves never shipped (validate_reason() already rejects version < 1
## from disk); this exists only to exercise the stepping machinery, see tests/test_save.gd.
## Stamps version and otherwise passes the doc through unchanged.
static func migrate_v0_to_v1(doc: Dictionary) -> Dictionary:
	var out: Dictionary = doc.duplicate(true)
	out["version"] = 1
	return out


# ---------------------------------------------------------------------------
# Balance knobs — tolerant of Data/db/balance being absent (sim/data agents may still be mid-
# build in parallel; see docs/ARCHITECTURE.md §2, §7). Object.get() never errors on a missing
# property, unlike dot-access, which is why these go through Data.get("db") rather than Data.db.
# ---------------------------------------------------------------------------

func _offline_min_seconds() -> float:
	var offline: Variant = _balance_subdict("offline")
	if typeof(offline) != TYPE_DICTIONARY or not offline.has("min_seconds"):
		return DEFAULT_OFFLINE_MIN_SECONDS
	var v: Variant = offline["min_seconds"]
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return DEFAULT_OFFLINE_MIN_SECONDS
	return float(v)


func _autosave_seconds() -> float:
	return _balance_number("autosave_seconds", DEFAULT_AUTOSAVE_SECONDS)


func _balance_number(key: String, fallback: float) -> float:
	var db: Variant = Data.get("db")
	if typeof(db) != TYPE_DICTIONARY:
		return fallback
	var balance: Variant = db.get("balance", null)
	if typeof(balance) != TYPE_DICTIONARY or not balance.has(key):
		return fallback
	var v: Variant = balance[key]
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return fallback
	return float(v)


func _balance_subdict(key: String) -> Variant:
	var db: Variant = Data.get("db")
	if typeof(db) != TYPE_DICTIONARY:
		return null
	var balance: Variant = db.get("balance", null)
	if typeof(balance) != TYPE_DICTIONARY:
		return null
	return balance.get(key, null)
