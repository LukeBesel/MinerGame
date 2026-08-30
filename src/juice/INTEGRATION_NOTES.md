# Juice & Audio — Integration Notes

Module owner: juice agent. Files owned: `src/juice/**`, `tools/gen_audio.py`,
`assets/audio/**`, `tests/test_juice_audio_assets.gd`.

## What other modules get

### `AudioDirector` (autoload)

- Creates **Music** and **SFX** buses in `_ready()` (routed to Master) if missing.
  SettingsService can rely on bus names existing after boot; AudioDirector also
  applies volumes itself (see subscriptions) so double-applying is harmless.
- `AudioDirector.play(sfx: String, pitch_scale := 1.0, volume_db := 0.0)` — pinned
  names: `click, buy_small, buy_big, unlock, chime_clear, milestone, prestige,
  scrap, error, tab`. 12-voice pool on the SFX bus; the longest-running voice is
  stolen when all are busy. Frequent SFX (`click, buy_small, buy_big, scrap, tab,
  error`) get ±5% random pitch automatically; signature sounds stay pitch-exact.
  **UI: call `play("click")` on button presses and `play("tab")` on tab switches
  yourself** — there are no EventBus signals for those. `error` is for rejected
  actions (can't afford, etc.).
- `AudioDirector.set_intensity(x: float)` — 0..1 crossfade of three additive
  ambience loops (~2 s tweens, Music bus). Layer 1 audible from 0.05, layer 2
  from 0.4, layer 3 from 0.75. Driven automatically from `sim_stats` pps
  (log-scaled: 0→0, 1 pps→0.3, 30 pps→0.7, ≥300 pps→1.0, throttled ~1 s);
  external calls are fine too (e.g. menus forcing quiet).

### `Juice` (autoload)

Owns a `CanvasLayer` at layer 90 (`JuiceLayer`); everything on it is
`MOUSE_FILTER_IGNORE`, so it never eats clicks.

- `squash(c: Control)` — 0.92→1.0 elastic pop, pivot centered. UI should call
  this on purchase-button presses (Juice does not squash UI it doesn't own).
- `float_text(text: String, screen_pos: Vector2, color: Color)` — rises ~50 px
  with slight x-drift, fades over 0.9 s. Pooled, ≤30 live (oldest recycled).
- `coin_burst(screen_pos: Vector2)` — one-shot CPUParticles2D burst of 8–16
  amber squares with a gravity arc (0.6 s), frees itself. Compatibility-renderer
  safe (web). UI may call with exact button positions for tighter feedback.
- `count_up(label, from, to, fmt: Callable, duration := 0.35)` — from/to may be
  float **or** BigNum (duck-typed via `has_method("to_float")`). BigNums lerp on
  `to_float()` when both exponents < 300, otherwise snap to the target (beyond
  double precision a lerp would be garbage). `fmt` is called each step with the
  interpolated value (BigNum in, BigNum path; float in, float path); if it
  returns a String the label text is set to it, and the tween always lands
  exactly on `to` at the end. One active tween per label (restarts cleanly).
- `shake(strength := 1.0)` — decaying random jitter on
  `get_viewport().get_camera_3d()` `h_offset`/`v_offset` (~0.3 s, real-time
  decay so it reads correctly during slow-mo). Scaled by
  `SettingsService.screen_shake` (defaults 0.3 while the field is absent);
  no-op under `reduce_motion` or shake 0. Base offsets are captured/restored, so
  the world agent's camera rigs may use their own constant offsets safely —
  but should avoid re-writing `h_offset/v_offset` every frame (fighting).
- `slowmo(time_scale := 0.35, duration := 0.4)` — `Engine.time_scale` dip with
  smooth recovery (recovery tween ignores time scale). HARD no-op under
  `reduce_motion`. Single active handle: re-triggering restarts it, and 1.0 is
  always restored (also on `_exit_tree`).

## EventBus subscriptions

| Signal | AudioDirector | Juice |
|---|---|---|
| `money_spent(amount, ctx)` | buy_small / buy_big (BigNum `e >= 4` → big); ctx `"unlock"` skipped (unlock sting covers it) | — |
| `station_upgraded` | deferred fallback buy_small, only if no `money_spent` sound this frame (120 ms debounce) | coin burst at screen center (≥150 ms apart) + "+X/s" green float text at center-left once the next `sim_stats` shows the station's throughput delta |
| `station_unlocked` | `unlock` | — |
| `bottleneck_cleared` | `chime_clear` | `slowmo()` + `shake(0.6)` + green vignette flash `Color(0.25,0.64,0.3,0.18)`, 0.25 s fade |
| `milestone_reached` | `milestone` | "+{kp} KP" amber float text, top center |
| `prestige_performed` | `prestige` | triple burst (bigger center + two flanks) + `shake(1.0)` |
| `scrap_produced` | `scrap` at −10 dB, throttled ≥2 s | — |
| `sim_stats` | ambience intensity from `pps`, throttled ~1 s | caches per-station `throughput` for the "+X/s" delta |
| `settings_changed` | volume keys → bus volume (`linear_to_db`, mute < 0.01); numeric payload applied directly, else re-read from SettingsService | — |
| `part_sold` | intentionally **not** connected (too chatty) | — |

## Audio files (all generated, CC0 — `assets/audio/LICENSE_NOTES.md`)

Regenerate with `python3 tools/gen_audio.py` (deterministic, stdlib only).

| File | Duration | Size | Content |
|---|---|---|---|
| `click.wav` | 0.060 s | 5.2 KB | filtered UI tick |
| `buy_small.wav` | 0.160 s | 13.8 KB | two-note coin blip (B5→E6) |
| `buy_big.wav` | 0.360 s | 31.1 KB | rising A-major arpeggio + low thump |
| `unlock.wav` | 0.500 s | 43.1 KB | warm A-major chord swell + bell |
| `chime_clear.wav` | 0.900 s | 77.6 KB | **signature**: bell arpeggio D6-F#6-A6-D7 + shimmer tail |
| `milestone.wav` | 0.420 s | 36.2 KB | two-chord sting (D→G major) |
| `prestige.wav` | 1.200 s | 103.4 KB | big warm swell cresting into bells + sparkle |
| `scrap.wav` | 0.120 s | 10.4 KB | dull pitch-drop clunk |
| `error.wav` | 0.160 s | 13.8 KB | soft low double-blip (descending) |
| `tab.wav` | 0.080 s | 6.9 KB | tiny noise swish |
| `amb_hum_1.wav` | 4.000 s | 125.0 KB | room tone + 50 Hz transformer hum (seamless loop) |
| `amb_hum_2.wav` | 4.000 s | 125.0 KB | + rhythmic press thrum, 8 strokes/loop (seamless) |
| `amb_hum_3.wav` | 4.000 s | 125.0 KB | + clatter/tick texture, low level (seamless) |

One-shots are 44.1 kHz / 16-bit / mono, peaks ≤ 0.68. Ambience layers are
**additive** (played simultaneously, faded in per intensity) and are 16 kHz so a
full 4 s seamless loop fits the <150 KB budget (DECISION-level deviation from
"all 44.1 kHz", recorded here; content is band-limited hum, inaudible loss).
Loops are seamless by construction (exact-cycle sines + events that decay before
the wrap); measured wrap step ≤ 0.4× the max in-signal step. Loop points are set
at load time (`AudioStreamWAV.loop_mode/begin/end`), not baked in the header.

## Guarded assumptions (parallel build)

- **SettingsService fields** (`master_volume, music_volume, sfx_volume,
  reduce_motion, screen_shake, number_format`) read via `get()` with defaults
  (1.0 volumes, `false`, 0.3, "suffix") — safe while the service is a stub.
- **BigNum** duck-typed: `has_method("to_float")`, `.get("e")`; `money_spent`
  amount tolerates plain int/float during bring-up.
- **`sim_stats` shape** guarded key-by-key (`pps`, `stations[i].throughput`);
  missing/odd shapes are ignored, never crash.
- If both `money_spent` and `station_upgraded` fire for one purchase, only one
  buy sound plays (debounce + deferred fallback). If only one of them fires, a
  sound still plays.
- WAVs load at runtime via `AudioStreamWAV.load_from_file` (4.4+ API; no
  `--import` needed, web-safe) with `load()` fallback for imported builds;
  missing files log one warning each and `play()` is a silent no-op.
- Reduce-motion behavior: slowmo/shake/burst/flash fully skipped; squash snaps
  to scale 1; float text fades in place (info kept, motion dropped); count_up
  snaps to the final formatted value.
- Camera/label/control freed mid-effect: `is_instance_valid` guards +
  `bind_node` tweens; shake state clears itself if the camera dies.

## Validation status (all run 2026-08-29)

- `python3 tools/gen_audio.py` — 13/13 files, all < 150 KB, peaks ≤ 0.68,
  loop-boundary continuity verified numerically.
- `--check-only` on both scripts: clean after the §2 autoload-name filter.
- Full suite `-s res://tests/run_tests.gd`: **13 passed / 0 failed (191
  asserts)** including new `tests/test_juice_audio_assets.gd` (format, duration,
  size-budget, presence — hermetic, no autoloads).
- Headless runtime smoke (scratchpad, not committed): booted all autoloads,
  created buses (Music=1, SFX=2), played SFX, emitted every subscribed signal,
  spammed 40 float texts (cap holds), double-called `slowmo` —
  `Engine.time_scale` restored to exactly 1.0; volume mute path verified. Zero
  script errors.
