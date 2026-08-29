# Bottleneck — Architecture Contract (v1)

This file is the **binding contract** between all modules. Every agent/developer reads this
before writing code. If you must deviate, record it in `docs/DECISIONS.md` with a `DECISION:`
line and note it in your module's `INTEGRATION_NOTES.md`.

Game: **Bottleneck** — a lean-manufacturing incremental/idle factory game. A linear production
line of stations connected by buffers; the slowest station is the bottleneck (Theory of
Constraints) and is always visually flagged. Money buys station upgrades; milestones grant
Kaizen Points spent on a lean skill tree; prestige ("Kaizen Event") grants Continuous
Improvement Points (CIP). 3D factory floor with a default orbit/management camera and a
first-person **Gemba Walk** mode. Ships on Steam ($4.99) + itch.io web demo.

Engine: **Godot 4.5 stable, GDScript** (typed where practical, tabs for indentation).
Local engine binary for validation: `/home/user/godot/godot`

---

## 1. Module map and ownership

| Path | Owner | Contents |
|---|---|---|
| `src/core/` | integrator | `main.tscn/gd` boot, `event_bus.gd`, `locale.gd`, `input_setup.gd` |
| `src/sim/` | sim agent | Pure simulation. **No scene nodes, no autoload references, no EventBus.** Unit-testable. |
| `src/data/` | data agent | `loader.gd` + all JSON definitions + `locale/en.json` |
| `src/world/` | world agent | 3D factory scenes/scripts: environment, stations, conveyors, cameras, 3D FX |
| `src/ui/` | ui agent | HUD CanvasLayer: top bar, panels, tabs, tooltips, coach, popups |
| `src/juice/` | juice agent | `juice.gd`, `audio_director.gd`, particles, tween helpers |
| `src/save/` | save agent | `save_manager.gd`, `settings_service.gd`, migrations, offline orchestration |
| `src/steam/` | save agent | `steam_bridge.gd` (safe no-op without Steam) |
| `tests/` | sim agent (+ others add their own `test_*.gd`) | headless tests, autoplayer |
| `steam/`, `build.sh`, `build.ps1`, `export_presets.cfg`, `.github/` | save agent | build/CI/Steamworks templates |
| `assets/` | juice agent (audio), integrator (misc) | generated audio, LICENSES notes |
| `marketing/` | marketing agent | store copy, capsule briefs, trailer script, launch checklist |

**Rules for every agent:**
- Do **not** create or edit files outside your owned paths (exception: add new `tests/test_<yourmodule>.gd`).
- Do **not** run `git` commands. The integrator owns version control.
- Do **not** edit `project.godot`, `docs/ARCHITECTURE.md`, or another module's files. If you need
  something from another module, code against this contract and write the need into
  `<your_path>/INTEGRATION_NOTES.md`.
- Every script starts with a 1–3 line `##` header comment explaining its role.
- All tunable numbers live in `src/data/*.json` — never hard-coded (visual-only constants are fine in code).
- Prefer boring, proven approaches. This has to ship.

## 2. Cross-module references — preload constants, not global class names

The global class-name cache is not reliable in headless/parallel workflows. Therefore:

- **No `class_name` declarations.** Reference other scripts with preload constants:
  ```gdscript
  const BigNum = preload("res://src/sim/big_num.gd")
  const SimTypes = preload("res://src/sim/sim_types.gd")
  var money: BigNum = BigNum.zero()      # preload consts work as type hints
  ```
- Autoload singletons (see §3) are referenced by name (`EventBus.sim_stats.emit(...)`) — but
  **only** outside `src/sim/` and `tests/`.

**Validation while you work** (from repo root; `--check-only` cannot resolve autoload names, so
filter those false positives — any *remaining* ERROR is real):
```bash
/home/user/godot/godot --headless --path . --check-only -s res://src/ui/hud.gd 2>&1 \
  | grep -E "ERROR" | grep -vE "Identifier not found: (L|Data|EventBus|SettingsService|Game|SaveManager|SteamBridge|AudioDirector|Juice)|Failed to load script"
```
Empty output = pass. Pure sim/tests scripts must pass with **no** filter.
Run the test suite (works today):
```bash
/home/user/godot/godot --headless --path . -s res://tests/run_tests.gd
```
Do **not** run `--import` or open the editor (it races with other agents on `.godot/`).

**GDScript headless gotchas — verified on this exact setup, follow or your code will not compile:**
1. `class_name` self-references do **not** resolve headless (no editor cache). Never declare
   `class_name`; never annotate with your own script's type inside its file. Inside static
   functions, construct instances with a bare `new()` (legal in 4.5) and call sibling statics
   bare (`make(...)`, not `BigNum.make(...)`).
2. Because of (1), cross-script preloaded APIs return `Variant`. **`var x := Foo.bar()` breaks**
   ("Cannot infer the type") whenever the right side is Variant — from BigNum ops, from any
   untyped return, or from attribute access on an untyped var. Use `var x = ...` or an explicit
   type (`var d: Dictionary = a.to_dict()`). When in doubt, use `=`.
3. A runtime script error aborts the rest of that function silently. The test runner therefore
   fails any test that recorded zero assertions — don't write assertion-free tests.
4. Autoloads DO load when running `-s res://tests/run_tests.gd` — but sim/tests code must still
   never reference them (keeps the suite hermetic and the sim pure).

## 3. Autoload registry (already configured in project.godot — do not edit)

Order matters. Names are fixed:

| Name | Script | Owner | Role |
|---|---|---|---|
| `L` | `src/core/locale.gd` | integrator | `L.t("key")`, `L.tf("key", [args])` string table from `src/data/locale/en.json` |
| `Data` | `src/data/loader.gd` | data agent | Loads/validates all JSON. `Data.db` dictionary, see §7 |
| `EventBus` | `src/core/event_bus.gd` | integrator | Signal hub (§5). One-way notifications only |
| `SettingsService` | `src/save/settings_service.gd` | save agent | User settings, `user://settings.json` (§10) |
| `Game` | `src/core/game.gd` | sim agent | Owns `SimEngine`, ticks it at 10 Hz, bridges sim events → EventBus. Command API (§6) |
| `SaveManager` | `src/save/save_manager.gd` | save agent | Autosave/rotation/migration/export-import/offline orchestration (§9) |
| `SteamBridge` | `src/steam/steam_bridge.gd` | save agent | GodotSteam wrapper; total no-op without Steam (§11) |
| `AudioDirector` | `src/juice/audio_director.gd` | juice agent | Buses, SFX by name, ambience layers (§12) |
| `Juice` | `src/juice/juice.gd` | juice agent | Squash/float-text/shake/slow-mo helpers honoring reduce-motion (§12) |

**Boot order** (implemented by `src/core/main.gd`, integrator): register input actions →
`Data` validated → `SaveManager.boot_load()` (loads newest valid save or starts new game;
computes offline progress) → world scene + HUD scene instanced → `EventBus.load_completed` →
offline popup if report present.

## 4. Fixed scene paths

| Scene | Root | Owner |
|---|---|---|
| `res://src/core/main.tscn` | `Node` "Main" | integrator |
| `res://src/world/factory_world.tscn` | `Node3D`, script `factory_world.gd` | world agent |
| `res://src/ui/hud.tscn` | `CanvasLayer`, script `hud.gd` | ui agent |

Main instances the world first, HUD second. Both must be self-contained: subscribe to EventBus
in `_ready()`, read state from `Game`, never assume the other exists, and survive
`EventBus.game_reset` (rebuild from `Game` state).

## 5. EventBus signal registry (exact names/args — see src/core/event_bus.gd)

10 Hz snapshot:
- `sim_stats(stats: Dictionary)` — see §6 for the snapshot shape. UI/world/audio read this; never poll Game per frame.

Sim transitions (emitted by Game from drained sim events):
- `part_completed(station: int)` — granular part finish; suppressed above `balance.visual.part_event_max_pps`
- `part_sold(count: float, revenue)` — revenue is a BigNum
- `scrap_produced(station: int, amount: float)`
- `bottleneck_changed(new_index: int, old_index: int)` — old_index -1 on first detection
- `bottleneck_cleared(station: int)` — **the signature moment** (slow-mo, green wave, chime)
- `station_status_changed(station: int, status: int)` — `SimTypes.STATUS_*`
- `station_upgraded(station: int, upgrade_id: String, levels: int, new_level: int)`
- `station_unlocked(station: int)`
- `money_spent(amount, context: String)` — amount is BigNum; context e.g. "upgrade", "unlock"
- `milestone_reached(id: String, kp_gained: int)`
- `kaizen_points_changed(total: float)`
- `skill_purchased(node_id: String)`
- `prestige_performed(cip_gained: int, new_multiplier: float)`
- `offline_report(report: Dictionary)` — `{seconds: float, capped: bool, parts, money}` (BigNums)

Interaction/UI:
- `station_selected(station: int)` — from 3D click or panel click; both world and UI react
- `buy_multiplier_changed(mult: int)` — 1 / 10 / 100 / `SimTypes.BUY_MAX` (-1)
- `coach_hint(text: String)` — already-localized hint for the Andon board
- `camera_mode_changed(mode: int)` — `SimTypes.CAMERA_ORBIT` / `CAMERA_WALK`
- `request_toast(text: String)`

Meta:
- `achievement_unlocked(id: String)`
- `save_completed(slot: String)` / `save_failed(reason: String)` / `load_completed()`
- `settings_changed(key: String, value)` 
- `game_reset()` — emitted after new game **and** after prestige; world/UI rebuild station views

Commands never travel on the bus — call `Game` methods (§6).

## 6. Game + SimEngine API (sim agent implements; everyone else consumes)

`src/sim/` is pure: RefCounted classes, no nodes, no autoloads, deterministic
(expected-value math; **no RNG in simulation results** — randomness is cosmetic-only in
world/juice). Fixed timestep `dt = 0.1` (10 Hz), accumulated by `Game` in `_process`.

`Game` (autoload, thin bridge):
```gdscript
var sim                                  # SimEngine instance (null until boot_load)
var buy_multiplier: int                  # 1|10|100|SimTypes.BUY_MAX
func new_game() -> void
func apply_loaded_state(state: Dictionary) -> bool   # from SaveManager
func serialize() -> Dictionary                       # for SaveManager
func offline_progress(seconds: float) -> Dictionary  # closed-form; returns offline report
func set_buy_multiplier(m: int) -> void
func buy_upgrade(station: int, upgrade_id: String) -> bool   # uses buy_multiplier
func unlock_station(station: int) -> bool
func buy_skill(node_id: String) -> bool
func do_prestige() -> bool
func get_station_view(station: int) -> Dictionary
func get_upgrade_view(station: int, upgrade_id: String) -> Dictionary
func get_prestige_view() -> Dictionary
func get_skill_state(node_id: String) -> Dictionary
func get_stats_snapshot() -> Dictionary   # same dict as last sim_stats emission
```

`sim_stats` snapshot shape (built once per tick, also returned by `get_stats_snapshot`):
```gdscript
{
  "money": BigNum, "pps": float, "oee": float,            # oee 0..1
  "bottleneck": int,                                       # station index, -1 if none
  "kp": float, "cip": int, "cip_mult": float,
  "lifetime_parts": BigNum, "scrap_total": float,
  "time_played": float, "prestige_count": int,
  "stations": Array[Dictionary],                           # station views, index-aligned, incl. locked
}
```

Station view:
```gdscript
{
  "index": int, "id": String, "name": String,              # name already localized
  "unlocked": bool, "status": int,                          # SimTypes.STATUS_*
  "is_bottleneck": bool,
  "stats": { "cycle_time": float, "uptime": float, "quality": float,
             "capacity": int, "changeover_time": float, "operator_count": int },
  "throughput": float,                                      # effective parts/sec
  "progress": float,                                        # 0..1 current cycle (for animation)
  "buffer_in": float, "buffer_in_cap": float,
  "scrap_rate": float,                                      # parts/sec lost to quality
  "upgrade_levels": Dictionary,                             # e.g. {"speed": 3, "machine": 1, ...}
  "unlock_cost": BigNum,                                    # meaningful when locked
}
```

Upgrade view (respects current `buy_multiplier`; BUY_MAX = as many as affordable, min 1 priced):
```gdscript
{ "cost": BigNum, "count": int, "affordable": bool, "maxed": bool, "helps_bottleneck": bool }
```

Prestige view:
```gdscript
{ "cip_current": int, "cip_gain": int, "multiplier_now": float, "multiplier_after": float,
  "lifetime_parts": BigNum, "min_parts": BigNum, "can_prestige": bool }
```

Skill state: `{ "purchased": bool, "available": bool, "affordable": bool, "cost": int }`

**Simulation rules (pinned):**
- Effective throughput of a station = `capacity * availability * quality / cycle_time * global_mults`,
  where `availability = uptime * (1 - changeover_time / balance.changeover_period_seconds)`, clamped ≥ 0.05.
- Bottleneck = unlocked station with lowest effective throughput (ties → lowest index).
- `bottleneck_cleared` fires when the bottleneck moves to a different station AND line pps
  strictly improved since that station became the bottleneck.
- Buffers sit before stations 1..N-1; capacity `balance.buffer_base_cap` × modifiers. A station
  is STARVED with an empty input buffer, BLOCKED when its output buffer is full. Station 0 has
  infinite raw material; the last station sells output instantly at `price_per_part` × price mults.
- Quality applied as continuous yield: a station finishing `k` parts forwards `k * quality`,
  scraps the rest (→ scrap events/rate).
- OEE = actual sold pps (rolling ~10 s) / ideal pps, where ideal = min over unlocked stations of
  `capacity / cycle_time` (perfect uptime/quality/changeover). Clamp 0..1.
- Cost curves: `cost(level) = base * growth^level`; bulk cost is the closed-form geometric sum.
  BUY_MAX buys the largest affordable count.
- Prestige: requires `lifetime_parts ≥ balance.prestige.min_lifetime_parts`. Total CIP earned for
  a lifetime-parts value: `floor((lifetime_parts / divisor) ^ exponent)`; gain = total − already earned.
  Global throughput multiplier = `1 + cip * multiplier_per_cip`. Reset: station levels/unlocks,
  money, buffers. **Persist:** skill tree, KP, CIP, lifetime stats, milestones, achievements, settings.
- Offline progress: closed-form `pps_steady × seconds` (capped at `offline.cap_hours` incl.
  modifiers, `× offline.rate`), plus passive KP. Must complete in < 50 ms.
- KP passive income and the CI-manager auto-buyer run inside `tick()`; auto-buyer greedily buys
  the affordable upgrade with best Δthroughput/cost at its configured interval.
- Sim events are queued internally and drained by Game each tick via `sim.drain_events()` →
  `Array[Dictionary]` like `{"t": "bottleneck_cleared", "station": 2}` — the `t` values mirror
  the EventBus transition signal names.

`SimTypes` constants (`src/sim/sim_types.gd`): `STATUS_IDLE=0, STATUS_RUNNING=1, STATUS_STARVED=2,
STATUS_BLOCKED=3`, `CAMERA_ORBIT=0, CAMERA_WALK=1`, `BUY_MAX=-1`.

`BigNum` (`src/sim/big_num.gd`) — already implemented, mantissa/exponent, immutable ops:
`BigNum.zero() / make(m,e) / from_float(x) / from_dict(d)`, methods `add(o) sub(o) mul(o)
mul_f(f) div(o) cmp(o) lt le gt ge eq is_zero neg clone to_float() to_dict()`,
static `from_pow(base: float, exp: float)`, `format(mode := "suffix", decimals := 2)`
(modes "suffix": 1.23K/M/B/T then aa..zz; "scientific": 1.23e45). Extend, don't rewrite the API.

## 7. Data files (data agent) — `src/data/`

`loader.gd` (autoload `Data`): static `load_all() -> Dictionary` and `validate(db) -> Array[String]`
usable **without** the autoload (tests call them directly); the autoload `_ready()` fills
`Data.db` and `push_error`s validation failures. `Data.db` keys: `stations` (Array),
`skills` (Array), `milestones` (Array), `achievements` (Array), `balance` (Dict), `hints` (Array).
Also provide `Data.station(id)`, `Data.skill(id)` lookups.

**stations.json** — 6 stations, pinned ids/order: `press`("Stamping Press"), `lathe`("CNC Lathe"),
`weld`("Weld Cell") — these 3 start unlocked — then `paint`("Paint Booth"), `assembly`("Assembly
Cell"), `pack`("QA & Packout") purchasable with money:
```jsonc
{ "schema_version": 1, "stations": [ {
  "id": "press", "name_key": "station.press", "order": 0,
  "unlock_cost": 0,                          // number or {"m":1.2,"e":3}
  "base": { "cycle_time": 4.0, "uptime": 0.85, "quality": 0.90,
            "capacity": 1, "changeover_time": 60.0, "operator_count": 1 },
  "upgrades": {
    "speed":   { "name_key": "upgrade.speed",   "base_cost": 10, "growth": 1.10,
                 "effect": { "stat": "cycle_time",      "op": "mul",        "value": 0.93 }, "max_level": 0 },
    "machine": { "name_key": "upgrade.machine", "base_cost": 60, "growth": 1.15,
                 "effect": { "stat": "capacity",        "op": "add",        "value": 1 },    "max_level": 24 },
    "tooling": { "name_key": "upgrade.tooling", "base_cost": 30, "growth": 1.12,
                 "effect": { "stat": "quality",         "op": "toward_one", "value": 0.10 }, "max_level": 40 },
    "smed":    { "name_key": "upgrade.smed",    "base_cost": 45, "growth": 1.12,
                 "effect": { "stat": "changeover_time", "op": "mul",        "value": 0.88 }, "max_level": 30 }
  } } ] }
```
Upgrade ids are pinned: exactly `speed`, `machine`, `tooling`, `smed` on every station.
`max_level: 0` = unlimited. Effect ops: `mul` (stat × value per level), `add` (+value per level),
`toward_one` (x' = x + (1−x)·value, applied per level — for 0..1 stats, asymptotic).

**skill_tree.json** — 40–60 nodes, five branches pinned: `flow`, `reliability`, `quality`,
`speed`, `people`:
```jsonc
{ "schema_version": 1, "nodes": [ {
  "id": "kanban_pull", "branch": "flow", "row": 1,
  "name_key": "skill.kanban_pull.name", "tip_key": "skill.kanban_pull.tip",  // one-line real-world explanation
  "cost": 2, "prereqs": ["conveyors_1"],
  "effects": [ { "type": "buffer_cap_mult", "value": 0.5 },
               { "type": "global_throughput_mult", "value": 1.05 } ] } ] }
```
Effect vocabulary (sim implements exactly these types):
`stat_mult` {stat, scope: "all"|"station:<id>", value}, `stat_toward_one` {stat, scope, value},
`stat_add` {stat, scope, value}, `global_throughput_mult` {value}, `price_mult` {value},
`upgrade_cost_mult` {value}, `offline_cap_add_hours` {value}, `offline_rate_mult` {value},
`kp_passive_per_min` {value}, `buffer_cap_mult` {value}, `scrap_refund_frac` {value},
`starting_money_add` {value}, `auto_buyer` {interval: seconds}, `unlock_feature` {feature: String}.

**milestones.json** — one-time, each grants KP:
```jsonc
{ "schema_version": 1, "milestones": [
  { "id": "first_100_parts", "name_key": "ms.first_100_parts", "kp": 1,
    "trigger": { "type": "lifetime_parts", "value": 100 } } ] }
```
Trigger vocabulary (sim implements): `lifetime_parts`, `money_earned`, `pps`, `oee`,
`bottleneck_cleared_count`, `station_unlocked` (value: station id), `upgrade_count`,
`skill_count`, `prestige_count`, `zero_scrap_seconds`.

**achievements.json** — 25–35 entries, `"id"` matching `^ACH_[A-Z0-9_]+$` (Steamworks IDs),
same trigger vocabulary plus `name_key`/`desc_key`.

**balance.json** — every global knob, pinned keys:
```jsonc
{ "schema_version": 1,
  "price_per_part": 1.0, "starting_money": 15,
  "tick_rate": 10, "buffer_base_cap": 100, "changeover_period_seconds": 600,
  "offline": { "cap_hours_base": 8, "rate": 1.0, "min_seconds": 60 },
  "prestige": { "min_lifetime_parts": 50000, "divisor": 10000, "exponent": 0.5, "multiplier_per_cip": 0.10 },
  "autosave_seconds": 30,
  "visual": { "part_event_max_pps": 8 },
  "pacing": { "first_prestige_target_minutes": [25, 50] } }
```

**hints.json** — Coach/Andon hints, priority-ordered, condition vocabulary kept simple
(ui agent implements the evaluator against `sim_stats`):
`{ "id", "priority": int, "cooldown_s": float, "text_key",
   "cond": { "type": "station_starved_seconds"|"bottleneck_stuck_seconds"|
             "affordable_bottleneck_upgrade"|"kp_unspent"|"can_prestige"|"always", "value": ... } }`

**locale/en.json** — flat `{ "key": "text" }`, `{0}`-style placeholders. Every `*_key` used in
any data file must exist here. UI code never hard-codes English strings — always `L.t()`.

## 8. World layer (world agent) — `src/world/`

Build everything from primitives/CSG/generated meshes and `StandardMaterial3D` — **no imported
binary assets**. Look: clean low-poly industrial, dark floor, emissive accents, glow, SSAO
(Forward+; must degrade silently on gl_compatibility for web).

- `factory_world.tscn/gd`: WorldEnvironment (tonemap, glow, ssao, subtle fog), lights, floor/walls,
  builds one `StationView3D` per station along +X, conveyor segments between them, rebuilds on
  `game_reset`/`load_completed`.
- Stations: distinct silhouettes per id (press ram, lathe spindle, weld arm + spark particles,
  paint booth, assembly arms, packout scanner). Animate via `progress` from `sim_stats` views.
- Status telegraphing (color + icon, colorblind-safe, from `sim_stats`):
  bottleneck → pulsing red-orange `#E4572E` beacon + "!" `Label3D`; STARVED → grey `#9AA0A6`
  + "Zz"; BLOCKED → amber `#F4B942` + "■"; healthy RUNNING → green `#3FA34D` LED, no icon.
- Conveyors: parts as `MultiMeshInstance3D` boxes moving at belt speed ∝ upstream throughput;
  WIP pile before each station grows/shrinks with `buffer_in`; red scrap bin fill ∝ scrap.
  Cap visible instances; above `visual.part_event_max_pps` represent flow, don't do 1:1 parts.
- Cameras: `OrbitCameraRig` (default; RMB-drag orbit, wheel zoom, MMB/edge pan, smooth follow of
  line extent — fully mouse-playable) and `WalkController` (CharacterBody3D, WASD + mouse-look,
  `toggle_walk` action = Tab, cannot leave the floor). Both raycast-click stations →
  `EventBus.station_selected.emit(index)`. Emit `camera_mode_changed`.
- `bottleneck_cleared`: green pulse wave expanding along the line + beacon celebration. (Juice
  owns slow-mo/audio; world owns 3D visuals.) Honor `SettingsService.reduce_motion`.

Input actions already registered by core: `move_forward/back/left/right`, `toggle_walk`,
`interact`, `pause_menu`.

## 9. Save layer (save agent) — `src/save/`

- Autosave every `balance.autosave_seconds` + on quit (`NOTIFICATION_WM_CLOSE_REQUEST`).
- Rotate `user://saves/save_0.json` → `_1` → `_2` (3 backups). Save doc:
  `{ "version": 1, "saved_at_unix": int, "app": "bottleneck", "sim": <Game.serialize()> }`.
  BigNums serialize as `{"m": float, "e": int}` everywhere.
- `boot_load()`: newest valid save wins; corrupt → try older backups, then new game + toast.
  After `apply_loaded_state`, compute `elapsed = now − saved_at_unix`; if ≥ `offline.min_seconds`,
  call `Game.offline_progress(elapsed)` and emit `offline_report`.
- Migration registry: `const MIGRATIONS = { 1: Callable }` style, applied stepwise
  `version → version+1`. Never break old saves; add a test per migration.
- Export/import string: `"BNK1." + Marshalls.utf8_to_base64(JSON)` with validation on import.
- `settings_service.gd`: `user://settings.json`, fields pinned: `master_volume, music_volume,
  sfx_volume` (0..1), `reduce_motion: bool=false`, `screen_shake: float=0.3`,
  `number_format: "suffix"|"scientific"`, `camera_sensitivity: float=1.0`. Emits
  `settings_changed` per key on change; applies volumes via AudioServer bus names §12.

## 10. Steam layer (save agent) — `src/steam/steam_bridge.gd`

- Detect GodotSteam at runtime (`ClassDB.class_exists("Steam")` / `Engine.has_singleton("Steam")`).
  Absent (itch/web/dev) → every method is a logged no-op; the game must never notice.
- `app_id` from `src/data/steam.json` (`{"app_id": 480}` placeholder). Init on boot; expose
  `available: bool`, `set_achievement(id)`, `store_stats()`. Listen for `achievement_unlocked`.
- Cloud conflict flow: stub + `steam/README.md` describing the prompt (local vs cloud, timestamps
  + lifetime parts). Provide `steam/app_build.vdf`, `steam/depot_build.vdf` templates, and
  export presets for Windows x86_64, Linux x86_64, macOS universal (note signing/notarization),
  Web; `build.sh`/`build.ps1` export+zip; CI workflow runs the headless tests.

## 11. Audio + juice (juice agent) — `src/juice/`

- Buses created in code: `Master`, `Music`, `SFX`. SFX are small generated WAVs, committed via
  `tools/gen_audio.py` (CC0, documented in `assets/audio/LICENSE_NOTES.md`).
- `AudioDirector.play(name: String, pitch_scale := 1.0)` — pinned names: `click, buy_small,
  buy_big, unlock, chime_clear, milestone, prestige, scrap, error, tab`. Ambience:
  `AudioDirector.set_intensity(x: float)` (0..1, from pps thresholds; layered factory hum).
- `Juice` helpers (all honor `reduce_motion` / `screen_shake` settings):
  `squash(control: Control)`, `float_text(text: String, screen_pos: Vector2, color: Color)`,
  `coin_burst(screen_pos: Vector2)`, `shake(strength := 1.0)`,
  `slowmo(time_scale := 0.35, duration := 0.4)`, `count_up(label: Label, from, to, fmt: Callable)`.
- Juice subscribes to EventBus itself (purchases → squash+burst+sound scaled by spend;
  `bottleneck_cleared` → slow-mo + `chime_clear`; milestones → sting).

## 12. UI layer (ui agent) — `src/ui/`

- `hud.tscn` (CanvasLayer): top bar (money w/ tweened count-up, parts/sec, OEE %, current
  bottleneck name + icon, KP), left panel (station cards: stats, 4 upgrade buttons w/ cost,
  unlock button for locked stations, highlight the upgrade that helps the bottleneck), buy
  multiplier toggle x1/x10/x100/MAX, right panel tabs (Skill Tree — 5 branch columns w/
  prereq lines; Kaizen Event — prestige preview + confirm; Stats; Settings — volume sliders,
  reduce motion, screen shake, number format, save export/import dialog), Coach/Andon board
  (one hint at a time from `hints.json`, evaluator on `sim_stats`), offline "While you were
  away" popup with count-up, toasts.
- Every string via `L.t()`/`L.tf()`. Numbers via `BigNum.format(SettingsService.number_format)`.
- Tooltips on hover with 0.4 s delay: name + one-line real-world lean explanation + effect + cost.
- Theme built in code or one `.tres` (dark industrial, amber accent `#F4B942`); readable at
  1280×720 through 4K and Steam Deck 1280×800. Keyboard focus navigation must work.
- Defensive: every handler guards `if Game.sim == null: return`.

## 13. Tests — `tests/`

- Framework: `tests/test_framework.gd` (extend via
  `extends "res://tests/test_framework.gd"`), methods named `test_*`, synchronous only.
  Asserts: `assert_true/assert_false/assert_eq/assert_near/fail`.
- Runner: `/home/user/godot/godot --headless --path . -s res://tests/run_tests.gd`
  (auto-discovers `tests/test_*.gd`; exit code 1 on failure). Keep the suite < 60 s.
- Required coverage: BigNum math+format; throughput/bottleneck; buffer conservation
  (parts in = parts out + scrap + WIP); cost curves incl. bulk-buy closed form; effects
  vocabulary; milestones; prestige formula; offline calc (incl. cap + <50 ms perf); save
  migration/rotation/import-export; data integrity (all keys exist in locale, prereqs valid,
  growth in 1.05–1.2, 40–60 skill nodes, 25–35 achievements, effect/trigger types in vocab).
- `tests/autoplayer.gd`: greedy bot on a pure SimEngine (no autoloads) — every 5 sim-seconds
  buys best Δthroughput/cost among station upgrades/unlocks, spends KP on cheapest available
  skill, stops at first prestige. `tests/test_pacing.gd` runs it at max speed, prints
  `AUTOPLAY t=<s> event=<id>` lines, asserts first prestige lands inside
  `balance.pacing.first_prestige_target_minutes` and that ≥ 6 distinct unlock/milestone events
  happen in the first 15 sim-minutes.

## 14. Style

- GDScript, tabs, typed where practical, `snake_case`. `##` header comment on every file.
- No `class_name` (see §2). No `await` in sim or tests.
- Visual scripts read `sim_stats`; never call into sim internals directly (`Game` API only).
- Colors/palette: bg `#17191D`, floor `#23262B`, panel `#1E2126`, text `#E8EAED`, accent amber
  `#F4B942`, good green `#3FA34D`, bad red-orange `#E4572E`, starved grey `#9AA0A6`.
