# Save / Steam / Pipeline — Integration Notes

Owner: save agent. Covers `src/save/**`, `src/steam/**`, `src/data/steam.json`, `steam/**`,
`export_presets.cfg`, `build.sh`, `build.ps1`, `.github/workflows/ci.yml`,
`tests/test_save.gd`, `tests/test_settings.gd`. Read `docs/ARCHITECTURE.md` §9/§10 first — this
file only records what that contract doesn't already say, plus the current validation status.

## Save doc format

```jsonc
{
  "version": 1,
  "saved_at_unix": 1735500000,
  "app": "bottleneck",
  "sim": { /* whatever Game.serialize() returns — opaque to SaveManager */ }
}
```

`SaveManager` never inspects the contents of `sim` beyond checking it's a `Dictionary` — that
shape is entirely the sim agent's `Game.serialize()` / `Game.apply_loaded_state()` contract.
BigNums inside it serialize as `{"m": float, "e": int}` per §9 (that's `BigNum.to_dict()`'s
existing shape — nothing SaveManager needs to special-case).

Files on disk: `user://saves/save_0.json` (newest) / `_1` / `_2`, rotated on every `save()` call
(`save_1→save_2`, then `save_0→save_1`, then fresh content written to `save_0`). Autosave runs
every `balance.autosave_seconds` (falls back to 30s if `Data.db` isn't populated yet); a save also
happens on `NOTIFICATION_WM_CLOSE_REQUEST` before the app is allowed to quit
(`get_tree().set_auto_accept_quit(false)` in `_ready()`).

Export string: `"BNK1." + Marshalls.utf8_to_base64(JSON.stringify(doc))` — `SaveManager.export_string()`/`import_string()`.

## Migration how-to (for the next SAVE_VERSION bump)

Today `SAVE_VERSION := 1` and `MIGRATIONS` has exactly one *synthetic* entry (`0 →
migrate_v0_to_v1`, a no-op used only by `tests/test_save.gd` to exercise the stepping machinery —
v0 saves never shipped, and `validate_reason()` already rejects `version < 1` from disk, so that
step never actually runs against a real save). To add a real migration when the save shape needs
to change:

1. Bump `const SAVE_VERSION` in `src/save/save_manager.gd` (e.g. `1 → 2`).
2. Add `static func migrate_v1_to_v2(doc: Dictionary) -> Dictionary:` next to
   `migrate_v0_to_v1` — pure, takes/returns a plain `Dictionary`, must not mutate its argument
   (`doc.duplicate(true)` first, same as the existing step), must set `out["version"] = 2`.
3. Register it: add `1: "migrate_v1_to_v2"` to the `MIGRATIONS` const dict.
4. Add a matching `"migrate_v1_to_v2":` case to the `match` inside `static func _migrate()`
   calling the new step — the dict entry and the match case must stay in lockstep (this two-place
   registration is a deliberate tradeoff: GDScript has no `class_name` self-reference to build a
   `Callable` dictionary of static methods without an editor-resolved global class cache — see
   ARCHITECTURE.md §2 — so dispatch is a small `match` instead of reflection. It's still real
   stepwise dispatch, not hidden behind version-specific `if`s scattered through the codebase).
5. Add a `tests/test_save.gd` case for the new step (mirrors
   `test_migrate_v0_to_v1_stamps_version_and_preserves_data`), and update
   `test_migrations_registry_has_a_step_for_every_version_below_current` needs no change — it
   already walks `0..SAVE_VERSION-1` generically.
6. Old saves at any version `< SAVE_VERSION` migrate automatically on next load (`boot_load()` →
   `_apply_loaded_doc()` → `_migrate()`) and on `import_string()`. Nothing else in the codebase
   needs to know the migration happened.

## Validation status

- `tests/test_save.gd` (19 tests) and `tests/test_settings.gd` (9 tests) are green, hermetic
  (construct synthetic dicts, no `user://` I/O, no `Game`/sim dependency — verified by preloading
  only the two autoload scripts + `steam_bridge.gd`'s pure `resolve_cloud_conflict`, never
  touching the scene tree). Run: `BNK_TEST_FILTER=save /home/user/godot/godot --headless --path .
  -s res://tests/run_tests.gd` (also matches `test_settings.gd`).
- All three autoload scripts pass the filtered `--check-only` command from ARCHITECTURE §2. Note:
  running `--check-only` directly on `tests/test_save.gd`/`test_settings.gd` themselves leaves one
  extra residual line, `SCRIPT ERROR: Compile Error: Failed to compile depended scripts.`, even
  after applying the documented filter — that's the same "`--check-only` can't resolve autoload
  names" limitation ARCHITECTURE §2 already documents, just surfacing one level up because these
  tests `preload()` autoload scripts (to reach their static helpers) rather than referencing
  autoload names directly. It disappears with one more filter term
  (`... | grep -vE "...|Failed to load script|Failed to compile depended scripts"`). The
  authoritative check is the actual test run, which is clean.
- `Marshalls.base64_to_utf8`/`JSON.parse_string` log `ERROR:` lines to stdout when fed the
  deliberately-corrupt input in the "corrupt JSON handling" test cases (e.g.
  `test_import_string_rejects_garbage_after_valid_prefix`) — that's the engine's own error
  reporting for a caught, handled failure, not a test failure; the tests themselves `PASS`.
- Full-suite run at hand-off: 121 passed / 3 failed (`test_milestones.gd`,
  `test_pacing.gd` — balance/pacing tuning, sim+data agents' territory, unrelated to this module).
  Mid-session there was also a brief spike of ~58 failures across every `src/sim/`-dependent test
  file ("no assertions executed") while `src/sim/sim_engine.gd` had a live timestamp matching a
  concurrent edit — a snapshot of another agent's in-progress write in this shared tree, not
  something this module caused or needs to react to; it had cleared by the next run.
  `test_save.gd`/`test_settings.gd` were unaffected throughout both runs (28/28), which is the
  intended payoff of keeping them hermetic.
- `export_presets.cfg`: hand-authored (no editor access — "no editor, no `--import`" per the task
  brief). Section/key names are verified against strings embedded in the actual Godot 4.5 binary
  (`strings /home/user/godot/godot | grep ...`), not guessed. One dry-run
  `--export-release "Windows Desktop"` confirmed the preset parses and is accepted up to the
  expected point — it failed only on missing export templates
  (`No export template found at .../export_templates/4.5.stable/windows_release_x86_64.exe`),
  which also confirms `4.5.stable` (dot notation, not the `4.5-stable` hyphenated release-tag
  form) is the correct local template directory name used in `.github/workflows/ci.yml`. That
  dry-run regenerates Godot's local `.godot/` cache and full-project `.import` sidecars as a side
  effect (this is what the "no editor / no --import" rule warns about) — this session cleaned up
  the `.wav.import`/`icon.svg.import` files it produced; `.godot/` itself is left as-is
  (gitignored, harmless, regenerable — every headless invocation including plain `--check-only`
  creates/touches it regardless). **Avoid re-running `--export-release` in this shared tree** —
  the one dry-run already answered what it needed to; advanced per-platform fields not set in the
  preset (icons, codesign identities, entitlements, PWA icons, …) fall back to the exporter's own
  defaults and should get one real interactive "Export" dialog pass once templates + real signing
  assets exist, to confirm/backfill them.
- `build.sh`: `bash -n` clean; ran end-to-end (`./build.sh`) — runs the real test suite, correctly
  detects the (genuinely absent, in this environment) export templates and exits 0 with a clear
  skip message, exactly per spec.
- `build.ps1`: mirrors `build.sh` logic 1:1; hand-verified only — no `pwsh` in this Linux sandbox
  to execute it.
- `.github/workflows/ci.yml`: YAML-parse-validated (`python3 -c "import yaml; ..."`). Caught and
  fixed one real bug this way: a single-line `run:` step had `"$HOME/godot-bin/godot"` quoted
  mid-value, which YAML parses as a complete quoted scalar followed by illegal trailing content —
  fixed by dropping the unnecessary quotes (the multi-line `run: |` steps elsewhere were never
  affected — block scalars don't get their contents re-parsed as YAML).

## What needs a real Steam app id / real GodotSteam

Everything in `src/steam/` and `steam/` is a structurally-complete no-op today: `available` is
`false` in every build this repo can currently produce because no GodotSteam GDExtension binary
is vendored here. To go live:

1. Follow `steam/README.md` §1 to get a real Steamworks App ID + Depot IDs, and replace the
   placeholders in `src/data/steam.json` and the three `steam/depot_build_*.vdf` files (`app_build.vdf`
   references them by depot id, not by filename, so only the depot files themselves need edits).
2. Add the GodotSteam GDExtension binary/addon to the project (outside this module's ownership —
   likely a `project.godot`/addons change, which is the integrator's call).
3. In `src/steam/steam_bridge.gd`, fill in the four `TODO(real GodotSteam)` blocks
   (`_init_steam()`, `set_achievement()`, `clear_achievement()`, `store_stats()`) — each is a
   single real GodotSteam call replacing a `print()` no-op; the surrounding `available` guard and
   control flow don't change.
4. `SteamBridge.check_cloud_conflict()` and `resolve_cloud_conflict()` exist and are tested, but
   `SaveManager.boot_load()` does not call them yet — there's no real Steam Cloud session to read
   a "cloud" save summary from without step 2. Once it exists, wire `check_cloud_conflict()` into
   boot (read the Cloud file, reduce it to `{saved_at_unix, lifetime_parts}`, compare) and have
   the UI agent build the actual prompt dialog described in `steam/README.md`'s "Cloud-conflict
   prompt" section.
5. Achievement ids: `src/data/achievements.json`'s `id` fields (pattern `^ACH_[A-Z0-9_]+$`,
   owned by the data agent) must exactly match the API Names entered in the Steamworks dashboard,
   sourced from `marketing/steamworks_achievements.md` (marketing agent) — see `steam/README.md` §1.5.

## Cross-module needs logged for other agents

- **Locale key** (data agent, `src/data/locale/en.json`): `save.corrupt_new_game` — shown via
  `EventBus.request_toast` when `boot_load()` finds only corrupt/invalid saves and starts a new
  game. Suggested English: *"Your save file was corrupted — starting a new game."* Until this key
  exists, `L.t()` harmlessly returns the raw key string (never crashes, per `src/core/locale.gd`'s
  documented tolerant behavior) — confirmed against the current (empty) locale file during
  testing, so this is a cosmetic gap, not a blocker.
- **AudioDirector** (juice agent, `src/juice/audio_director.gd`): call
  `SettingsService.apply_all_volumes()` once your `Music`/`SFX` buses are created. `SettingsService`
  boots *before* `AudioDirector` in the fixed autoload order (ARCHITECTURE §3), so its own
  boot-time volume application silently no-ops for those two buses (`AudioServer.get_bus_index`
  returns `-1` until they exist) — `"Master"` applies fine immediately since it's a built-in bus.
  `apply_all_volumes()` is public and re-reads the current `master_volume`/`music_volume`/
  `sfx_volume` values, so a single call after bus creation catches it up correctly.
- **UI agent** (`src/ui/`): the Settings tab should call `SettingsService.set_setting(key, value)`
  (or assign the property directly, e.g. `SettingsService.master_volume = x` — both paths clamp,
  emit `settings_changed`, and debounce-save identically) and the save-export/import dialog should
  call `SaveManager.export_string()` / `SaveManager.import_string(text)` (returns `bool`; on
  `false` a `save_failed` reason string was already emitted on `EventBus` for a toast).
- **World/UI Steam Deck checklist items** (controller focus traversal, on-screen legibility) are
  listed in `steam/README.md` §3 but are outside this module's ownership to verify — flagged there
  for whichever agent/pass covers Deck certification.

## Settings service quick reference

Pinned fields (all direct-property AND `set_setting(key, value)` accessible, both paths converge
on the same clamp → `EventBus.settings_changed` → debounced (~0.5s) `user://settings.json` write):
`master_volume`/`music_volume`/`sfx_volume` (float 0..1, defaults 0.8/0.6/0.8),
`reduce_motion` (bool, default false), `screen_shake` (float 0..1, default 0.3),
`number_format` (`"suffix"`|`"scientific"`, default `"suffix"`), `camera_sensitivity` (float,
default 1.0, clamped 0.1..3.0 — this range isn't pinned by ARCHITECTURE.md, chosen as a sane
default; adjust `CAMERA_SENS_MIN`/`MAX` in `settings_service.gd` if world/UI playtesting wants
different bounds). `SettingsService.force_save()` flushes immediately, bypassing the debounce —
`SaveManager` calls it on quit so a setting changed in the last <0.5s before close isn't lost.
