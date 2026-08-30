# src/sim — Integration Notes (sim agent)

## What was built

| File | Role |
|---|---|
| `src/sim/sim_engine.gd` | Pure RefCounted simulation core: fluid line flow, buffers, statuses, bottleneck + cleared detection, OEE, quality/scrap, selling, milestones/achievements, skills, KP, auto-buyer, prestige, offline closed form, serialize/load, event queue. Deterministic expected-value math, zero RNG, no nodes/autoloads/EventBus. |
| `src/sim/upgrade_math.gd` | Cost curves: `cost(level) = base * growth^level`, exact geometric bulk sums, O(1) BUY_MAX (log-space + slop verification). BigNum in/out. |
| `src/sim/effects.gd` | Folds purchased skill nodes into one modifier bundle; implements the full §7 effect vocabulary; applies scoped stat mods. Unknown types warn + no-op. |
| `src/sim/milestones.gd` | Trigger evaluator for the shared §7 trigger vocabulary (used for milestones AND achievements). Unknown types never fire. |
| `src/core/game.gd` | Autoload bridge (the only sim↔engine contact): accumulates `_process` delta into fixed 0.1 s ticks (frame delta clamped to 1 s), emits `sim_stats` per tick, maps `drain_events()` onto EventBus signals, exposes the full §6 command/view API, guards `sim == null` and empty `Data.db` everywhere. |
| `tests/` | `autoplayer.gd` (shared inline fixture db + greedy bot), `test_line.gd`, `test_upgrades.gd`, `test_effects.gd`, `test_milestones.gd`, `test_prestige.gd`, `test_offline.gd`, `test_pacing.gd`. `big_num.gd` / `sim_types.gd` untouched (API kept). |

## Contract compliance

Implements §6 exactly: API names/signatures, snapshot shape, station/upgrade/prestige/skill
views, throughput formula (`capacity * availability * quality / cycle_time * global_mults`,
`availability = uptime * (1 - changeover/period)` clamped to [0.05, 1]), bottleneck = slowest
unlocked station (ties → lowest index), `bottleneck_cleared` on move + strict line-pps
improvement since that station became the bottleneck, buffers before stations 1..N-1 with
cap × `buffer_cap_mult`, station 0 infinite raw, last unlocked station sells instantly,
continuous quality yield → scrap, OEE = rolling ~10 s actual sold pps / ideal (clamped 0..1),
geometric bulk pricing + closed-form BUY_MAX, prestige CIP `floor((lifetime/divisor)^exp)`
with gain = total − earned, reset/persist split per contract, closed-form offline with
cap/rate modifiers, KP passive + auto-buyer inside `tick()`, `drain_events()` `t` values
mirroring §5 signal names. All §2 headless rules followed (no `class_name`, bare `new()` in
statics, no `:=` on Variant expressions).

## Decisions & clarifications (no silent deviations)

1. **`achievement_unlocked` sim events.** §7 gives achievements the same trigger vocabulary
   and the db hands them to the sim, so the engine evaluates them and queues
   `{"t": "achievement_unlocked", "id"}`; Game maps it to the existing EventBus signal.
   Additive to the §6 event list.
2. **Pricing is contract-literal (flat).** Parts sell at `price_per_part × price_mults`,
   nothing else. **Design flag for the integrator:** with flat pricing, unlocking a station
   whose quality < 1 strictly *reduces* sold pps and revenue (extra yield stage), so the only
   rational unlock incentives are milestone/achievement KP. The greedy autoplayer therefore
   never unlocks paint/assembly/pack. If mid-game unlock pull feels weak in playtests, the
   one-line fix I recommend is value-add pricing (`price × unlocked_station_count`, the ToC
   "throughput = money rate" reading) — implemented and tested here once, then reverted to
   stay contract-literal and keep DATA's tuning valid; ask and I'll re-enable + retune.
3. **`can_prestige` additionally requires `cip_gain ≥ 1`** (plus the pinned lifetime-parts
   gate) so a player can never perform a zero-gain reset. `get_prestige_view()` exposes both.
4. **Unlocks are sequential** (`next_locked_index()` only) — the line is linear; a mid-line
   hole is meaningless. `load_state` normalizes non-prefix unlock flags away defensively.
5. **Prestige flushes buffer WIP** (fiction: the factory is sold). Tracked in `wip_flushed`
   so conservation stays exact: `started = sold + scrap + wip + flushed` (see
   `debug_totals()`, used by tests).
6. **`zero_scrap_seconds` is strict**: the streak accrues only while the line is actually
   producing AND per-tick scrap is ~0, and any scrap resets it. Reaching it requires quality
   exactly 1.0, which the vocabulary allows (`stat_toward_one` with value 1.0, or clamp).
   DATA: a `zero_scrap_seconds` milestone is only reachable if some skill/tooling path can
   hit quality 1.0 on every unlocked station.
7. **Two-sweep fluid flow.** Flow is resolved per tick with a downstream-first acceptance
   bound followed by an upstream-first propagation with same-tick pass-through. This keeps
   cap/STARVED/BLOCKED semantics but removes the hidden `buffer_cap / dt` throughput ceiling
   a naive per-tick buffer walk has (at cap 100 & 10 Hz that would hard-cap the game at
   1000 pps — late-game breaking). Statuses: RUNNING at full rate, STARVED when input-bound,
   BLOCKED when downstream-space-bound, IDLE when locked. Downstream of the bottleneck reads
   STARVED, upstream reads BLOCKED — exactly the Factorio-Bottleneck-style telegraphing the
   world layer wants.
8. **Event pacing:** `part_completed` is queued per whole good part per station and only
   while snapshot `pps ≤ balance.visual.part_event_max_pps`; `part_sold` and
   `scrap_produced` are batched to ~1/s (fractional counts possible at low pps — `count` is
   a float by contract). `kaizen_points_changed` fires on discrete changes and every whole
   passive point. Queue is capped at 4096 (oldest dropped) as a safety valve.
9. **Snapshot extras (additive):** `rps` (BigNum revenue/s) and `features` (Array of
   `unlock_feature` strings; also `get_feature_unlocked(name)`). Station views additionally
   carry `name_key`; station 0 reports `buffer_in`/`buffer_in_cap` = 0 (infinite raw).
10. **Localization:** the sim is autoload-free, so station views leave `name` = `name_key`;
    `Game` localizes `name` via `L.t()` in every view/snapshot it hands out.
11. **Costs accept both encodings.** `base_cost`/`unlock_cost`/trigger values may be plain
    numbers or `{"m","e"}` dicts — the DATA loader normalizes costs to dicts; regression
    test covers both (`test_costs_accept_bignum_dict_form`).
12. **Offline:** applies only when `seconds ≥ offline.min_seconds` (double-gate with
    SaveManager is harmless); report is `{seconds (credited), capped, parts, money}` plus
    additive `kp` and `raw_seconds`; scrap/refunds/KP-passive/milestones are included;
    the auto-buyer intentionally does not run offline. O(stations), measured far under 50 ms
    for any duration.
13. **Save format:** `serialize()` is version 1, pure JSON-safe data, BigNums as `{"m","e"}`;
    `Game.serialize()` adds `buy_multiplier` on top. `load_state` drops unknown ids, clamps
    levels/buffers, rejects only unusable input or future versions (SaveManager migrates
    before calling). The OEE window and event queue are transient (OEE refills within 10 s
    after load; loading queues no events).
14. **Numeric limits:** floats carry pps to ~1e300 (BigNum handles money/parts beyond);
    total CIP saturates at 4e18. Both are far beyond shipped content.

## What integration must wire

- **SaveManager**: `Game.new_game()` / `Game.apply_loaded_state(doc["sim"])` (bool result —
  on false try older backup; Game leaves current sim untouched), `Game.serialize()`,
  `Game.offline_progress(elapsed)` → SaveManager emits `offline_report` (Game does not).
- **Boot**: `Data.db` must be populated before `Game.new_game()`; Game logs and stays idle
  (`sim == null`) when it is missing/empty, per contract.
- **World/UI/Juice**: consume `sim_stats` + the mapped transition signals; every station view
  field their INTEGRATION_NOTES mention (status, progress, throughput, buffer_in,
  is_bottleneck, localized `name`, `unlock_cost`, `upgrade_levels`) is provided.
  `Game.get_upgrade_view` respects the current buy multiplier; `helps_bottleneck` is true
  only when the upgrade actually raises the bottleneck station's throughput.
- **On `game_reset` after prestige** the snapshot cache is refreshed *before* the signal, so
  rebuild handlers may safely call `Game.get_stats_snapshot()` inside it.

## Pacing status (measured, real data via `Data.load_all()`)

`tests/test_pacing.gd` runs the greedy autoplayer (5 s decision cadence, one purchase per
window, cheapest-skill KP spending) at max speed and prints `AUTOPLAY t=<s> event=<id>`
lines. With `src/data` as of 2026-08-29 20:11 (`min_lifetime_parts` 220000, divisor 50000):
**first prestige at 1695 s = 28.3 min** (target window 25–50 min → PASS) and **45 distinct
unlock/milestone events in the first 15 min** (≥ 6 → PASS). Note the DATA agent retuned
balance mid-build (12000 → 220000 min parts); the two-sweep flow fix (decision 7) is what
makes >500 pps — and therefore the new gate — reachable at all. If balance.json moves again,
re-run `BNK_TEST_FILTER=test_pacing` to re-verify the window.

## Validation status

Full suite (`/home/user/godot/godot --headless --path . -s res://tests/run_tests.gd`),
including the pre-existing `test_bignum.gd` and the other agents' test files present in the
tree, sim perf asserts (36 000 ticks ≈ 3.5 s < 5 s; 8 h offline < 50 ms) and the live-data
pacing run:

```
=== TESTS passed=125 failed=0 asserts=1376 in 9183ms ===
```
(125 = 9 bignum + 63 sim-agent tests across 7 files + the data/save/settings/ui/juice agents'
test files present at run time; `AUTOPLAY summary: prestige_time=1695.0s (target
1500..3000s) distinct_events_15min=45`.)

All sim scripts compile standalone with `--check-only` with zero errors (no filter);
`src/core/game.gd` passes with only the documented autoload-name false positives filtered.

## Extension pass — 2026-08-30 (rush orders, assist API, settings exception)

### Rush orders (`sim_engine.gd` + `game.gd`, data-driven via `db["orders"]`)

- **Mechanics.** At most one active order. Spawn gate (checked per tick): `time_played >=
  orders.start_after_seconds` AND `time_played >= ready_at` (cooldown since the last order
  *ended* — success, timeout, offline cancel or prestige) AND instantaneous `pps >=
  orders.min_pps`. Required parts = `round(estimate_steady_pps() x template.seconds x
  orders.duration_fraction_of_capacity)`, floored at 10 (`MIN_ORDER_PARTS`) — sized UNDER
  the pace the player already sustains, so every order is beatable and pushing ships it
  early. Progress counts sold parts (`pps x dt`) while active. Success pays
  `required x current sale price x (reward_mult - 1)` (BigNum; "current" price on purpose —
  a mid-order unlock under value-add pricing raises the payout) plus `kp_bonus`; timeout
  queues a failure and costs nothing. **The bonus is added to `money_earned` too** (it is
  income; `money_earned` triggers can see it — same treatment as scrap refunds).
- **Determinism (§6, no RNG).** The template is picked by rotating the persisted
  `order_rotation` counter over a weight-expanded index list built in `_setup_db`
  (weight 3 = three slots). Identical runs produce identical order sequences
  (test-enforced).
- **Events** queued/drained like everything else: `{"t":"order_started","id"}`,
  `{"t":"order_completed","id","reward":BigNum}`, `{"t":"order_failed","id"}`; Game maps
  them onto the pre-registered EventBus signals (reward passed through).
- **Views.** `sim.get_order_view()` -> `{}` when none, else `{id, name, name_key,
  required, progress (clamped to required), seconds_left, reward_mult, reward_preview:
  BigNum}`; `name` carries the raw `name_key` and `Game.get_order_view()` localizes it
  (station-view convention). The snapshot additionally carries the view under the
  additive key `"order"` (localized by Game's `_build_snapshot`).
- **Not offline, not through prestige.** `offline_progress` (past its min_seconds gate)
  silently cancels an active order — no failed event, the player wasn't there to miss it —
  and restarts the cooldown from `time_played` (which does not advance offline, so the
  cooldown runs in live play after return). A sub-`min_seconds` absence leaves the order
  untouched. Prestige (`_reset_run_state(false)`) also drops an in-flight order silently +
  restarts the cooldown (the factory was just sold).
- **Serialization (additive, still save version 1).** `order_rotation`,
  `order_ready_at`, `order_active` (pure JSON scalars). `load_state` defaults them when
  absent — pre-orders saves load unchanged — and resumes an active order only if its
  template still exists and `seconds_left > 0`; anything else is dropped silently.
- **Disabled gracefully.** Empty/missing `db["orders"]` (all test fixtures) = no orders,
  zero behavior change; that plus additive save keys is why every pre-existing test
  passes untouched.

### Assist API — the FIX IT backend

- `sim.best_bottleneck_fix() -> Dictionary`: `{}` when no bottleneck or no move would
  raise steady rps. Otherwise scores the bottleneck station's four tracks (one level
  each, max_level respected, `estimate_upgrade_delta_rps`) plus the next unlock
  (`estimate_unlock_delta_rps`, > 0 essentially only under value-add pricing) by
  delta-rps/cost (BigNum-safe) and returns the best AFFORDABLE move — or, when nothing is
  affordable, the best move overall with `"affordable": false` (UI shows "Save up — $X").
  Shape: pinned `{kind: "upgrade"|"unlock", station, upgrade_id ("" for unlock), cost:
  BigNum, affordable}` plus additive `name_key` (Game turns it into `label`) and
  `delta_rps` (tooltips). Because deltas are LINE deltas, the assist sees through
  upgrades that speed the station but not the line (test-enforced).
- `sim.apply_best_fix() -> bool` executes exactly that one purchase (one level / one
  unlock, always multiplier 1); refuses unaffordable fixes.
- `Game.get_best_fix_view()` adds localized `label` = upgrade display name or station
  name (via the additive `name_key`); `Game.apply_best_fix()` delegates to the sim (so
  the global buy multiplier can never leak in) and emits events/stats on success.

### Granted exception used

Per this pass's mandate, exactly two fields were added to `src/save/settings_service.gd`
following its existing pattern (property setter -> `clamp_field` funnel ->
`settings_changed` emit -> debounced save; in `default_settings`/`current_dict`/
`_apply_dict`/`set_setting`): `ui_mode: String` ("simple"|"advanced", default "simple",
`UI_MODES` const) and `onboarding_done: bool` (default false). Covered hermetically in
`tests/test_assist.gd::test_settings_ui_mode_and_onboarding_fields` via runtime `load()`
(keeps the test file clean under unfiltered `--check-only`; `test_settings.gd` untouched
and green).

### Pacing impact (measured, real data)

Scratch probe, greedy autoplayer on `Data.load_all()`: **without orders prestige=1715 s /
38 distinct events in 15 min; with orders prestige=1700 s / 38** (bot started 9 orders,
completed 8, failed 0 — they auto-complete at steady state by design, duration_fraction
0.7). Orders are a gentle accelerant (~1% on first prestige) — no balance retune needed;
the pinned gate passes with real margin. (The "45 distinct events" in older notes
predates the integrator's post-notes changes; 38 is today's baseline both with and
without orders.)

### Validation

Full suite: `=== TESTS passed=155 failed=0 asserts=1717 in ~9.3s ===` — the 126
pre-existing tests + this pass's 21 (10 `test_orders.gd` + 8 `test_assist.gd` + 3 new in
`test_data.gd`) + 8 the UI agent landed in `test_ui.gd` in parallel — including
test_save/test_settings and `AUTOPLAY summary: prestige_time=1700.0s (target
1500..3000s) distinct_events_15min=38`. `--check-only`: sim files, loader and both new
test files pass with NO filter; `game.gd`/`settings_service.gd` pass with only the
documented autoload-name false positives filtered.
