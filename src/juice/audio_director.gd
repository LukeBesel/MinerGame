## AudioDirector — audio buses, pooled SFX playback by pinned name, and the layered
## factory ambience that follows line speed. Autoload (ARCHITECTURE.md §11); subscribes
## to EventBus itself so gameplay code never has to think about sound.
extends Node

const AUDIO_DIR := "res://assets/audio/"
const SFX_NAMES := ["click", "buy_small", "buy_big", "unlock", "chime_clear",
		"milestone", "prestige", "scrap", "error", "tab"]
const AMB_NAMES := ["amb_hum_1", "amb_hum_2", "amb_hum_3"]
const POOL_SIZE := 12
## Frequent/spammable SFX get ±5% random pitch so repetition never grates.
## Signature sounds (unlock/chime_clear/milestone/prestige) stay pitch-exact.
const JITTER_SFX := ["click", "buy_small", "buy_big", "scrap", "tab", "error"]

# Ambience layer i becomes audible at THRESHOLD[i] and reaches full level
# FADE_RANGE[i] later; BASE_DB is each layer's full-level trim.
const AMB_THRESHOLDS := [0.05, 0.4, 0.75]
const AMB_FADE_RANGE := [0.30, 0.30, 0.25]
const AMB_BASE_DB := [-8.0, -11.0, -14.0]
const AMB_FADE_S := 2.0
const SILENT_DB := -60.0

const SCRAP_COOLDOWN_MS := 2000
const BUY_DEBOUNCE_MS := 120
const INTENSITY_THROTTLE_MS := 1000

var _streams: Dictionary = {}				# name -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _pool_started_ms: Array[int] = []
var _amb_players: Array[AudioStreamPlayer] = []
var _amb_tweens: Array = [null, null, null]
var _amb_gains: Array[float] = [0.0, 0.0, 0.0]
var _intensity: float = -1.0
var _last_scrap_ms: int = -100000
var _last_buy_ms: int = -100000
var _last_intensity_ms: int = -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load_streams()
	_build_pool()
	_build_ambience()
	_apply_all_volumes()
	EventBus.station_upgraded.connect(_on_station_upgraded)
	EventBus.money_spent.connect(_on_money_spent)
	EventBus.station_unlocked.connect(_on_station_unlocked)
	EventBus.bottleneck_cleared.connect(_on_bottleneck_cleared)
	EventBus.milestone_reached.connect(_on_milestone_reached)
	EventBus.prestige_performed.connect(_on_prestige_performed)
	EventBus.scrap_produced.connect(_on_scrap_produced)
	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.settings_changed.connect(_on_settings_changed)
	# part_sold: intentionally NOT connected — fires far too often to sonify.


## ------------------------------------------------------------------ public API

## Play a one-shot SFX by pinned name (click, buy_small, buy_big, unlock,
## chime_clear, milestone, prestige, scrap, error, tab).
func play(sfx: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sfx)
	if stream == null:
		return
	var p := _grab_player()
	if p == null:
		return
	var pitch := pitch_scale
	if JITTER_SFX.has(sfx):
		pitch *= randf_range(0.95, 1.05)
	p.stream = stream
	p.pitch_scale = maxf(0.05, pitch)
	p.volume_db = volume_db
	p.play()


## Crossfade the three ambience layers toward intensity x (0..1). Layer 1 is
## audible from 0.05, layer 2 from 0.4, layer 3 from 0.75; ~2 s smooth tweens.
func set_intensity(x: float) -> void:
	var xi := clampf(x, 0.0, 1.0)
	if _intensity >= 0.0 and absf(xi - _intensity) < 0.005:
		return
	_intensity = xi
	for i in _amb_players.size():
		var gain := clampf((xi - float(AMB_THRESHOLDS[i])) / float(AMB_FADE_RANGE[i]), 0.0, 1.0)
		_fade_layer(i, gain)


## ------------------------------------------------------------------ bus / setup

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _load_streams() -> void:
	var all_names: Array = SFX_NAMES + AMB_NAMES
	for n: String in all_names:
		var path := AUDIO_DIR + n + ".wav"
		var stream := _load_wav(path)
		if stream == null:
			push_warning("AudioDirector: could not load %s (run tools/gen_audio.py?)" % path)
			continue
		if AMB_NAMES.has(n) and stream is AudioStreamWAV:
			var w := stream as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = _frame_count(w)
		_streams[n] = stream


## Runtime WAV load (no --import in this workflow); falls back to the resource
## loader for imported builds. Returns null when the file is absent.
func _load_wav(path: String) -> AudioStream:
	if FileAccess.file_exists(path):
		var w := AudioStreamWAV.load_from_file(path)
		if w != null:
			return w
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			return res
	return null


func _frame_count(w: AudioStreamWAV) -> int:
	var bytes_per_sample := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var channels := 2 if w.stereo else 1
	return w.data.size() / (bytes_per_sample * channels)


func _build_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.name = "SfxPlayer%d" % i
		add_child(p)
		_pool.append(p)
		_pool_started_ms.append(-1)


func _grab_player() -> AudioStreamPlayer:
	var oldest_i := 0
	var oldest_ms := 9223372036854775807
	for i in _pool.size():
		if not _pool[i].playing:
			_pool_started_ms[i] = Time.get_ticks_msec()
			return _pool[i]
		if _pool_started_ms[i] < oldest_ms:
			oldest_ms = _pool_started_ms[i]
			oldest_i = i
	# All busy: steal the longest-running voice.
	_pool_started_ms[oldest_i] = Time.get_ticks_msec()
	return _pool[oldest_i]


func _build_ambience() -> void:
	for i in AMB_NAMES.size():
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.name = "Ambience%d" % (i + 1)
		p.volume_db = SILENT_DB
		var stream: AudioStream = _streams.get(AMB_NAMES[i])
		if stream != null:
			p.stream = stream
		add_child(p)
		_amb_players.append(p)


func _fade_layer(i: int, gain: float) -> void:
	var p := _amb_players[i]
	if p == null or not is_instance_valid(p) or p.stream == null:
		return
	_amb_gains[i] = gain
	var target_db := SILENT_DB
	if gain > 0.001:
		target_db = float(AMB_BASE_DB[i]) + linear_to_db(gain)
		target_db = maxf(target_db, SILENT_DB)
		if not p.playing:
			p.volume_db = SILENT_DB
			p.play(randf() * maxf(p.stream.get_length(), 0.001))
	var old: Variant = _amb_tweens[i]
	if old != null and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target_db, AMB_FADE_S) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if gain <= 0.001:
		tw.tween_callback(_stop_layer_if_silent.bind(i))
	_amb_tweens[i] = tw


func _stop_layer_if_silent(i: int) -> void:
	if i < 0 or i >= _amb_players.size():
		return
	var p := _amb_players[i]
	if p != null and is_instance_valid(p) and _amb_gains[i] <= 0.001:
		p.stop()


## ------------------------------------------------------------------ volumes

const VOLUME_KEY_TO_BUS := {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "SFX"}


func _on_settings_changed(key: String, value: Variant) -> void:
	if not VOLUME_KEY_TO_BUS.has(key):
		return
	# Prefer the signal payload (works even while SettingsService fields are
	# still landing); fall back to re-reading the whole service.
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		_apply_bus_volume(VOLUME_KEY_TO_BUS[key], clampf(float(value), 0.0, 1.0))
	else:
		_apply_all_volumes()


func _apply_all_volumes() -> void:
	_apply_bus_volume("Master", _setting_f("master_volume", 1.0))
	_apply_bus_volume("Music", _setting_f("music_volume", 1.0))
	_apply_bus_volume("SFX", _setting_f("sfx_volume", 1.0))


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	if linear < 0.01:
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


## SettingsService is built in parallel — read fields defensively.
func _setting_f(prop: String, default_value: float) -> float:
	var ss := get_node_or_null("/root/SettingsService")
	if ss == null:
		return default_value
	var v: Variant = ss.get(prop)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return clampf(float(v), 0.0, 1.0)
	return default_value


## ------------------------------------------------------------------ event handlers

func _on_money_spent(amount: Variant, context: String) -> void:
	if context == "unlock":
		return	# station_unlocked plays the richer unlock sting instead
	_play_buy(_magnitude_e(amount))


## Fallback for the case where a purchase emits station_upgraded without
## money_spent (modules land in parallel). Deferred so that if money_spent DID
## fire this frame, its magnitude-aware sound wins and the debounce eats this one.
func _on_station_upgraded(_station: int, _upgrade_id: String, _levels: int, _new_level: int) -> void:
	call_deferred("_deferred_buy_fallback")


func _deferred_buy_fallback() -> void:
	_play_buy(0)


func _play_buy(exponent: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_buy_ms < BUY_DEBOUNCE_MS:
		return
	_last_buy_ms = now
	if exponent >= 4:
		play("buy_big")
	else:
		play("buy_small")


## Duck-typed BigNum exponent (amount.e); tolerates plain numbers during bring-up.
func _magnitude_e(amount: Variant) -> int:
	if typeof(amount) == TYPE_OBJECT and amount != null:
		var ev: Variant = amount.get("e")
		if ev != null:
			return int(ev)
	if typeof(amount) == TYPE_FLOAT or typeof(amount) == TYPE_INT:
		var f := absf(float(amount))
		if f >= 1.0:
			return int(floor(log(f) / log(10.0)))
	return 0


func _on_station_unlocked(_station: int) -> void:
	play("unlock")


func _on_bottleneck_cleared(_station: int) -> void:
	play("chime_clear")


func _on_milestone_reached(_id: String, _kp_gained: int) -> void:
	play("milestone")


func _on_prestige_performed(_cip_gained: int, _new_multiplier: float) -> void:
	play("prestige")


func _on_scrap_produced(_station: int, _amount: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_scrap_ms < SCRAP_COOLDOWN_MS:
		return
	_last_scrap_ms = now
	play("scrap", 1.0, -10.0)


func _on_sim_stats(stats: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_intensity_ms < INTENSITY_THROTTLE_MS:
		return
	_last_intensity_ms = now
	var pps := 0.0
	var v: Variant = stats.get("pps")
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		pps = float(v)
	set_intensity(_pps_to_intensity(pps))


## Log-scaled pps -> ambience intensity: 0 pps -> 0, ~1 -> 0.3, ~30 -> 0.7, >=300 -> 1.
func _pps_to_intensity(pps: float) -> float:
	if pps <= 0.0:
		return 0.0
	if pps < 1.0:
		return 0.3 * sqrt(pps)
	var l := log(pps) / log(10.0)
	if pps <= 30.0:
		return lerpf(0.3, 0.7, l / 1.4771)
	if pps <= 300.0:
		return lerpf(0.7, 1.0, (l - 1.4771) / 1.0)
	return 1.0
