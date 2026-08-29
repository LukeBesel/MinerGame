## Game — autoload bridge between the pure SimEngine and the engine/EventBus (the ONLY place
## they meet). Accumulates _process delta into fixed 0.1 s ticks, emits sim_stats each tick,
## and maps the sim's drained event queue onto EventBus transition signals. Commands come here.
extends Node

const SimEngine = preload("res://src/sim/sim_engine.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")

const MAX_FRAME_DELTA := 1.0	# clamp runaway frame delta (window drag, debugger pause)
const VALID_MULTIPLIERS := [1, 10, 100, SimTypes.BUY_MAX]

var sim = null	# SimEngine instance (null until new_game/apply_loaded_state)
var buy_multiplier: int = 1

var _acc: float = 0.0
var _last_snapshot: Dictionary = {}


func _process(delta: float) -> void:
	if sim == null:
		return
	_acc += minf(delta, MAX_FRAME_DELTA)
	var ticked := false
	while _acc >= SimTypes.TICK_DT:
		_acc -= SimTypes.TICK_DT
		sim.tick(SimTypes.TICK_DT)
		ticked = true
	if ticked:
		_emit_events()
		_emit_stats()


# ------------------------------------------------------------------ lifecycle

## Start a fresh run from Data.db. If data is missing/empty, log and stay idle (sim == null).
func new_game() -> void:
	var db := _get_db()
	if db.is_empty():
		push_warning("Game.new_game: Data.db missing or empty — staying idle")
		return
	sim = SimEngine.new_game(db)
	buy_multiplier = 1
	_acc = 0.0
	_last_snapshot = {}
	EventBus.game_reset.emit()
	_emit_events()
	_emit_stats()


## Restore a serialized state (from SaveManager). On failure the current sim is left
## untouched and false is returned so the caller can try an older backup.
func apply_loaded_state(state: Dictionary) -> bool:
	var db := _get_db()
	if db.is_empty():
		push_warning("Game.apply_loaded_state: Data.db missing or empty")
		return false
	var engine = SimEngine.new_game(db)
	var ok: bool = engine.load_state(state)
	if not ok:
		push_warning("Game.apply_loaded_state: rejected save state")
		return false
	sim = engine
	var m: int = int(state.get("buy_multiplier", 1))
	buy_multiplier = m if VALID_MULTIPLIERS.has(m) else 1
	_acc = 0.0
	_last_snapshot = {}
	EventBus.game_reset.emit()
	_emit_events()
	_emit_stats()
	return true


## Save-state dictionary for SaveManager (BigNums already {"m","e"} dicts).
func serialize() -> Dictionary:
	if sim == null:
		return {}
	var out: Dictionary = sim.serialize()
	out["buy_multiplier"] = buy_multiplier
	return out


## Closed-form offline progression; returns the report dict (SaveManager emits offline_report).
func offline_progress(seconds: float) -> Dictionary:
	if sim == null:
		return {}
	var report: Dictionary = sim.offline_progress(seconds)
	_emit_events()
	_emit_stats()
	return report


# ------------------------------------------------------------------ commands

func set_buy_multiplier(m: int) -> void:
	if not VALID_MULTIPLIERS.has(m) or m == buy_multiplier:
		return
	buy_multiplier = m
	EventBus.buy_multiplier_changed.emit(m)


func buy_upgrade(station: int, upgrade_id: String) -> bool:
	if sim == null:
		return false
	var ok: bool = sim.buy_upgrade(station, upgrade_id, buy_multiplier)
	if ok:
		_emit_events()
		_emit_stats()
	return ok


func unlock_station(station: int) -> bool:
	if sim == null:
		return false
	var ok: bool = sim.unlock_station(station)
	if ok:
		_emit_events()
		_emit_stats()
	return ok


func buy_skill(node_id: String) -> bool:
	if sim == null:
		return false
	var ok: bool = sim.buy_skill(node_id)
	if ok:
		_emit_events()
		_emit_stats()
	return ok


func do_prestige() -> bool:
	if sim == null:
		return false
	var ok: bool = sim.do_prestige()
	if ok:
		_emit_events()
		# Refresh the cached snapshot BEFORE game_reset so rebuild handlers that call
		# get_stats_snapshot() see the post-prestige state, then broadcast it.
		_last_snapshot = _build_snapshot()
		EventBus.game_reset.emit()
		EventBus.sim_stats.emit(_last_snapshot)
	return ok


# ------------------------------------------------------------------ views

func get_station_view(station: int) -> Dictionary:
	if sim == null:
		return {}
	var view: Dictionary = sim.get_station_view(station)
	_localize_station(view)
	return view


func get_upgrade_view(station: int, upgrade_id: String) -> Dictionary:
	if sim == null:
		return {}
	return sim.get_upgrade_view(station, upgrade_id, buy_multiplier)


func get_prestige_view() -> Dictionary:
	if sim == null:
		return {}
	return sim.get_prestige_view()


func get_skill_state(node_id: String) -> Dictionary:
	if sim == null:
		return {}
	return sim.get_skill_state(node_id)


## Same dictionary as the last sim_stats emission (fresh-built if none yet).
func get_stats_snapshot() -> Dictionary:
	if sim == null:
		return {}
	if _last_snapshot.is_empty():
		_last_snapshot = _build_snapshot()
	return _last_snapshot


# ------------------------------------------------------------------ internals

func _emit_stats() -> void:
	_last_snapshot = _build_snapshot()
	EventBus.sim_stats.emit(_last_snapshot)


func _build_snapshot() -> Dictionary:
	var snap: Dictionary = sim.get_stats_snapshot()
	for view in snap.get("stations", []):
		_localize_station(view)
	return snap


func _localize_station(view: Dictionary) -> void:
	if view.has("name_key"):
		view["name"] = L.t(str(view["name_key"]))


func _emit_events() -> void:
	var events: Array = sim.drain_events()
	for ev_v in events:
		var ev: Dictionary = ev_v
		match str(ev.get("t", "")):
			"part_completed":
				EventBus.part_completed.emit(int(ev["station"]))
			"part_sold":
				EventBus.part_sold.emit(float(ev["count"]), ev["revenue"])
			"scrap_produced":
				EventBus.scrap_produced.emit(int(ev["station"]), float(ev["amount"]))
			"bottleneck_changed":
				EventBus.bottleneck_changed.emit(int(ev["new_index"]), int(ev["old_index"]))
			"bottleneck_cleared":
				EventBus.bottleneck_cleared.emit(int(ev["station"]))
			"station_status_changed":
				EventBus.station_status_changed.emit(int(ev["station"]), int(ev["status"]))
			"station_upgraded":
				EventBus.station_upgraded.emit(int(ev["station"]), str(ev["upgrade_id"]),
						int(ev["levels"]), int(ev["new_level"]))
			"station_unlocked":
				EventBus.station_unlocked.emit(int(ev["station"]))
			"money_spent":
				EventBus.money_spent.emit(ev["amount"], str(ev["context"]))
			"milestone_reached":
				EventBus.milestone_reached.emit(str(ev["id"]), int(ev["kp_gained"]))
			"kaizen_points_changed":
				EventBus.kaizen_points_changed.emit(float(ev["total"]))
			"skill_purchased":
				EventBus.skill_purchased.emit(str(ev["node_id"]))
			"prestige_performed":
				EventBus.prestige_performed.emit(int(ev["cip_gained"]), float(ev["new_multiplier"]))
			"achievement_unlocked":
				EventBus.achievement_unlocked.emit(str(ev["id"]))
			_:
				push_warning("Game: unknown sim event '%s'" % str(ev.get("t", "")))


func _get_db() -> Dictionary:
	if not ("db" in Data):
		return {}
	var db: Variant = Data.db
	if typeof(db) != TYPE_DICTIONARY:
		return {}
	var stations: Variant = (db as Dictionary).get("stations", [])
	if typeof(stations) != TYPE_ARRAY or (stations as Array).is_empty():
		return {}
	return db
