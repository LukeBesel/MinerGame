## SteamBridge — thin wrapper around GodotSteam, detected at runtime. Every public call below is
## a clean, logged no-op when Steam/GodotSteam isn't present (itch/web/dev builds) so the rest of
## the game never has to branch on whether Steam exists — see docs/ARCHITECTURE.md §10.
## Wiring real GodotSteam later is a one-file change: fill in the TODO-marked calls below.
extends Node

const STEAM_JSON_PATH := "res://src/data/steam.json"
## Valve's public "Spacewar" test app id — safe to build against, must never ship. Real id comes
## from src/data/steam.json.
const DEFAULT_APP_ID := 480

## available is false in every build this repo can produce today (no GodotSteam GDExtension
## binary is vendored here) — that is intentional, not a bug; see INTEGRATION_NOTES.md.
var available: bool = false
var app_id: int = DEFAULT_APP_ID
var _steam_singleton: Object = null


func _ready() -> void:
	app_id = _load_app_id()
	available = _detect_steam()
	if available:
		_init_steam()
	else:
		print("SteamBridge: GodotSteam not present — running Steam-free (itch/web/dev build).")
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)


func _detect_steam() -> bool:
	return Engine.has_singleton("Steam") or ClassDB.class_exists("Steam")


func _init_steam() -> void:
	_steam_singleton = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	if _steam_singleton == null:
		push_warning("SteamBridge: 'Steam' class exists but no singleton instance — treating as unavailable.")
		available = false
		return
	# TODO(real GodotSteam): initialize with app_id, e.g.
	#   var init_result: Dictionary = _steam_singleton.steamInitEx(app_id)
	#   available = int(init_result.get("status", 1)) == 0
	#   if not available:
	#       push_warning("SteamBridge: steamInitEx failed: %s" % str(init_result.get("verbal", "")))
	print("SteamBridge: Steam detected, app_id=%d (real GodotSteam init wiring pending)." % app_id)


func _load_app_id() -> int:
	if not FileAccess.file_exists(STEAM_JSON_PATH):
		push_warning("SteamBridge: %s missing, using default app_id %d" % [STEAM_JSON_PATH, DEFAULT_APP_ID])
		return DEFAULT_APP_ID
	var f := FileAccess.open(STEAM_JSON_PATH, FileAccess.READ)
	if f == null:
		return DEFAULT_APP_ID
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("app_id"):
		return DEFAULT_APP_ID
	var v: Variant = parsed["app_id"]
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return DEFAULT_APP_ID
	return int(v)


# ---------------------------------------------------------------------------
# Public API — every call below is a safe, logged no-op when `available` is false.
# ---------------------------------------------------------------------------

## Unlocks a Steamworks achievement by its API name (matches achievements.json's "id", e.g.
## "ACH_FIRST_100_PARTS"). Mirrors the real Steamworks API shape: this does not itself flush to
## the backend — call store_stats() after (the achievement_unlocked handler below already does).
func set_achievement(id: String) -> void:
	if not available:
		print("SteamBridge: (no-op, no Steam) set_achievement(%s)" % id)
		return
	# TODO(real GodotSteam): _steam_singleton.setAchievement(id)
	print("SteamBridge: set_achievement(%s)" % id)


func clear_achievement(id: String) -> void:
	if not available:
		print("SteamBridge: (no-op, no Steam) clear_achievement(%s)" % id)
		return
	# TODO(real GodotSteam): _steam_singleton.clearAchievement(id)
	print("SteamBridge: clear_achievement(%s)" % id)


## Flushes pending achievement/stat changes to the Steamworks backend.
func store_stats() -> void:
	if not available:
		print("SteamBridge: (no-op, no Steam) store_stats()")
		return
	# TODO(real GodotSteam): _steam_singleton.storeStats()
	print("SteamBridge: store_stats()")


func _on_achievement_unlocked(id: String) -> void:
	set_achievement(id)
	store_stats()


# ---------------------------------------------------------------------------
# Steam Cloud conflict resolution — see steam/README.md for the exact prompt this drives.
# ---------------------------------------------------------------------------

## Allows the "newer" save to look up to ~0.1% behind on lifetime_parts before treating it as a
## real conflict (swallows float/offline-calc timing noise, not real divergent progress).
const CLOUD_CONFLICT_TOLERANCE := 1.001

## Decides how to resolve a Steam Cloud vs local save conflict, given lightweight summaries of
## each: {"saved_at_unix": int, "lifetime_parts": float}. Returns:
##   "local" / "cloud" — the two agree closely enough (the newer save is also the same-or-more
##                        progressed) that picking it silently is safe; no prompt needed.
##   "ask"             — the OLDER-by-timestamp save has meaningfully MORE lifetime_parts than
##                        the newer one (divergent play on two machines, or a rollback) — picking
##                        either silently risks discarding real progress. Show the player the
##                        prompt documented in steam/README.md before touching either save.
## Pure/static — see tests/test_save.gd-style coverage expectations in INTEGRATION_NOTES.md.
static func resolve_cloud_conflict(local: Dictionary, cloud: Dictionary) -> String:
	var l_time: float = float(local.get("saved_at_unix", 0))
	var c_time: float = float(cloud.get("saved_at_unix", 0))
	var l_parts: float = float(local.get("lifetime_parts", 0))
	var c_parts: float = float(cloud.get("lifetime_parts", 0))

	if l_time <= 0.0 and c_time <= 0.0:
		return "local"
	if l_time <= 0.0:
		return "cloud"
	if c_time <= 0.0:
		return "local"

	var newer: String = "local" if l_time >= c_time else "cloud"
	var newer_parts: float = l_parts if newer == "local" else c_parts
	var older_parts: float = c_parts if newer == "local" else l_parts

	if newer_parts * CLOUD_CONFLICT_TOLERANCE >= older_parts:
		return newer
	return "ask"


## Boot-time cloud-vs-local check. No-op today (always "local" — there is no real Steam Cloud
## session to compare against without the GodotSteam binary). Once wired: read the Cloud file's
## save doc, reduce it to a {saved_at_unix, lifetime_parts} summary, and call
## resolve_cloud_conflict(local_summary, cloud_summary). SaveManager does not call this yet —
## see src/save/INTEGRATION_NOTES.md.
func check_cloud_conflict(local_summary: Dictionary) -> String:
	if not available:
		return "local"
	# TODO(real GodotSteam): var cloud_summary := _read_cloud_summary()
	#   return resolve_cloud_conflict(local_summary, cloud_summary)
	return "local"
