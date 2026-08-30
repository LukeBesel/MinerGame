# UI module — integration notes

Owner: ui agent. Everything under `src/ui/` plus `tests/test_ui.gd`.
`res://src/ui/hud.tscn` is exactly a CanvasLayer root named "HUD" with `hud.gd`; the whole
interface is built in code in `_ready()` — there are no other scenes.

## Control tree

```
HUD (CanvasLayer, layer 10)                      hud.tscn → hud.gd
└─ Root (Control, full-rect, mouse IGNORE)       owns the one Theme (ui_theme.gd, §14 palette)
   ├─ TopBar        top_bar.gd                   anchors (0,0→1,0), h 56: money (count-up),
   │                                             parts/sec, OEE, bottleneck chip (clickable), KP
   ├─ Coach         coach.gd                     anchored top-center; Andon board, one hint at a
   │                                             time, slide-in, click to dismiss
   ├─ StationPanel  station_panel.gd             left column w 372: buy-multiplier x1/x10/x100/MAX
   │  └─ StationCard × N  station_card.gd        status icon+name, thr/quality/WIP row, 4 upgrade
   │                                             buttons (amber glow = helps bottleneck+affordable),
   │                                             locked → one big Unlock button
   ├─ RightPanel    right_panel.gd               right column w 436: custom tab strip →
   │  ├─ SkillTreePanel  skill_tree_panel.gd     5 branch columns, prereq connector lines (_draw),
   │  │                                          states owned/ready(pulse)/available/locked
   │  ├─ KaizenPanel     kaizen_panel.gd         prestige preview + confirm step + congrats state
   │  ├─ StatsPanel      stats_panel.gd          lifetime stats + per-station throughput table
   │  └─ SettingsPanel   settings_panel.gd       audio/motion/format/sensitivity + save export/import
   ├─ Overlay (Control, IGNORE)                  modal home: OfflinePopup (offline_popup.gd),
   │                                             SaveModal (built by settings_panel.gd)
   ├─ Toasts        toasts.gd                    bottom-right stack, never blocks 3D clicks
   └─ TooltipLayer  tooltip.gd                   shared tooltip: 0.4 s hover, focus (Deck), 0.5 s
                                                 long-press; every registered control routes here
```

- All rendering comes from `EventBus.sim_stats` (plus transition signals); nothing polls `Game`
  per frame. Every panel also refreshes once from `Game.get_stats_snapshot()` on
  `load_completed` / `game_reset` so the HUD is never blank between ticks.
- Full-screen wrappers are mouse-IGNORE; only real panels STOP the mouse, so 3D station
  clicks pass through everywhere else.
- Keyboard/controller: everything is focusable (cards themselves too, `ui_accept` selects),
  scroll containers use `follow_focus`, focus is a 2 px amber outline, modals grab focus on
  open and close on `ui_cancel`. Tooltips also appear on keyboard focus (Deck without mouse).
- Numbers: `BigNum.format(SettingsService.number_format)` via `ui_util.gd`; accepts BigNum
  objects, `{"m","e"}` dicts and plain floats.

## Coach / hints.json evaluator semantics (data agent, please confirm)

- **Priority: a HIGHER `priority` int wins**; ties resolve to file order. One hint on screen
  at a time; a strictly-higher-priority hint may replace it after 3 s minimum display.
- `cooldown_s` starts when the hint is shown and restarts when it is dismissed by click
  (default 30 s when the field is missing). A visible hint auto-hides once its condition has
  been false for ~4 s.
- Condition types implemented exactly as pinned in §7: `station_starved_seconds` (any
  unlocked station continuously starved ≥ value), `bottleneck_stuck_seconds` (same bottleneck
  index ≥ value), `affordable_bottleneck_upgrade` (any non-maxed affordable upgrade on the
  current bottleneck, checked at 2 Hz), `kp_unspent` (kp ≥ value **and** at least one
  available+affordable skill exists, checked at 1 Hz, so the hint never points at a dead
  end), `can_prestige`, `always`.
- `EventBus.coach_hint(text)` is emitted with the localized text each time a new hint shows.

## Guarded-API assumptions (degrade gracefully until modules land)

- `Game`: every handler checks `Game.sim != null` (via `"sim" in Game` + null) and
  `has_method()` before calling `buy_upgrade / unlock_station / buy_skill / do_prestige /
  set_buy_multiplier / get_*_view / get_skill_state / get_stats_snapshot`.
  `buy_multiplier` is read as a property when present; `buy_multiplier_changed` is mirrored.
- `SettingsService`: reads are property lookups with defaults (`number_format`,
  `reduce_motion`, `screen_shake`, volumes, `camera_sensitivity`). Writes try, in order:
  `set_setting(key, value)` → `set_value(key, value)` → direct property set + optional
  `save()` + a self-emitted `settings_changed` (stub-era only). **Save agent: exposing
  `set_setting(key, value)` makes the fallback path dead code.**
- `SaveManager`: `export_string()` / `import_string(s)` behind `has_method`; an import result
  is treated as bool when it is one. **Assumption: `offline_report` is emitted after the HUD
  is instanced** (boot order §3 puts the popup after `load_completed`); if it ever fires
  earlier the popup misses it.
- `Juice.count_up(label, from, to, fmt)` is used only for big money jumps (> +25 % in one
  tick) and skipped under reduce-motion; otherwise the label is set directly (10 Hz).
- `AudioDirector.play` is guarded; the UI uses only pinned names `click`, `tab`, `error`
  (purchase/milestone/prestige audio is Juice's own EventBus reaction).
- `Data.db` guarded via `("db" in Data)`; missing db → skill tree shows an empty note,
  upgrade names fall back to `upgrade.<id>` locale keys, hints stay silent.
- All tunables rendered (costs, priorities, cooldowns, effects) come from `Data.db` /
  `Game` views; the only constants in `src/ui` are visual (sizes, delays, colors).

## Cross-module issue observed during integration (sim agent) — RESOLVED

Early sim revisions read `float(u.get("base_cost"))` while `loader.gd` normalizes
`base_cost`/`unlock_cost` to BigNum dicts `{"m","e"}`, which made every
`get_upgrade_view()` call abort ("Nonexistent 'float' constructor") against the real db.
The sim agent fixed this mid-session; verified from the UI side afterwards: cards render
live costs ($4 / $20 / $8 / $9 on the press at t=0), a button press buys and charges
(15.1 → 11.1, speed Lv 0 → 1), and a locked station shows "Unlock · $30K". Keeping this
note only as a reminder that sim unit tests feed hand-built float-cost dbs — an
integration boot (`BNK_SMOKE=1`) is what catches loader-shape regressions.

## Locale keys

Keys already in `src/data/locale/en.json` are used as-is (including `ui.buy_mult_*`,
`ui.running/starved/blocked/idle`, `ui.cycle_time/capacity/operators`, `ui.prestige_*`,
`ui.toast_save_ok/fail`, `ui.number_format_*`, `ui.settings_export_save/import_save`,
`ui.cancel/confirm/close`, `ui.orbit_hint/walk_hint`, and `ui.per_sec` as a plain "/s"
suffix, not a template). `ui.offline_body` is used with `{0}` = money, `{1}` = duration.

**EXTRA keys to merge** (all currently missing from en.json; suggested English below —
tooltips follow pillar 3: plain English + the real lean term, standalone):

```json
{
	"ui.ok": "OK",
	"ui.no_data": "Nothing here yet.",
	"ui.money_amount": "${0}",
	"ui.kp_amount": "{0} KP",
	"ui.mult_value": "x{0}",
	"ui.dur_h": "{0}h",
	"ui.dur_m": "{0}m",
	"ui.dur_s": "{0}s",
	"ui.offline_parts": "Parts produced: {0}",
	"ui.prestige_done_title": "Kaizen Event complete!",
	"ui.prestige_done_body": "+{0} CI Points — the whole line now runs at {1}.",
	"ui.stats_multiplier": "Line Multiplier",
	"ui.stats_stations": "Per-Station Throughput",
	"ui.settings_audio": "Audio",
	"ui.settings_display": "Display",
	"ui.settings_controls": "Controls",
	"ui.settings_save": "Save Data",
	"ui.settings_copy": "Copy",
	"ui.settings_paste": "Paste",
	"ui.settings_apply": "Apply",
	"ui.settings_paste_here": "Paste your save string here…",
	"ui.toast_copied": "Copied to clipboard.",
	"ui.toast_achievement": "Achievement unlocked: {0}",
	"ui.toast_milestone": "Milestone: {0} (+{1})",
	"ui.branch_flow": "Flow",
	"ui.branch_reliability": "Reliability",
	"ui.branch_quality": "Quality",
	"ui.branch_speed": "Speed",
	"ui.branch_people": "People",
	"ui.scope_all": "all stations",
	"ui.scope_station": "{0} only",
	"ui.effect_stat_mult": "{0} {1} ({2})",
	"ui.effect_stat_toward_one": "{0} closes {1} of the gap to 100% ({2})",
	"ui.effect_stat_add": "{0} +{1} ({2})",
	"ui.effect_global_throughput_mult": "Whole line {0}",
	"ui.effect_price_mult": "Sale price {0}",
	"ui.effect_upgrade_cost_mult": "Upgrade costs {0}",
	"ui.effect_offline_cap_add_hours": "+{0}h offline cap",
	"ui.effect_offline_rate_mult": "Offline earnings {0}",
	"ui.effect_kp_passive_per_min": "+{0} Kaizen Points per minute",
	"ui.effect_buffer_cap_mult": "Buffer capacity {0}",
	"ui.effect_scrap_refund_frac": "{0} of scrapped parts refunded",
	"ui.effect_starting_money_add": "+{0} starting money after a Kaizen Event",
	"ui.effect_auto_buyer": "CI manager buys the best upgrade every {0}s",
	"ui.effect_unlock_feature": "Unlocks: {0}",
	"ui.upeffect_mul": "{0} {1} per level",
	"ui.upeffect_add": "{0} {1} per level",
	"ui.upeffect_toward_one": "{0} closes {1} of the gap to 100% per level",
	"ui.tip_money": "Cash from sold parts. Spend it on station upgrades and unlocks.",
	"ui.tip_pps": "Finished parts sold per second at the end of the line.",
	"ui.tip_oee": "Overall Equipment Effectiveness: actual output vs. the line's theoretical best. World-class plants hit ~85%.",
	"ui.tip_bottleneck": "The slowest station sets the pace of the whole line (Theory of Constraints). Fix it first — click to jump to it.",
	"ui.tip_kp": "Kaizen Points — earned at milestones. Spend them in the Skill Tree.",
	"ui.tip_cip": "Continuous Improvement Points from Kaizen Events. Each one permanently speeds up every future factory.",
	"ui.tip_buy_mult": "How many upgrade levels each click buys. MAX buys as many as you can afford.",
	"ui.tip_throughput": "Good parts this station finishes per second.",
	"ui.tip_quality": "Share of parts that pass inspection. The rest become scrap.",
	"ui.tip_wip": "Work In Progress waiting in front of this station. A full buffer blocks the station upstream.",
	"ui.tip_unlock": "Extends the line with a new station. A longer line sells parts for more.",
	"ui.tip_upgrade_speed": "Faster cycles (takt time): the machine finishes each part sooner.",
	"ui.tip_upgrade_machine": "Adds a parallel machine so the station works several parts at once.",
	"ui.tip_upgrade_tooling": "Better tooling and poka-yoke: fewer defects, less scrap.",
	"ui.tip_upgrade_smed": "Quick changeover (SMED): swap tooling in seconds instead of minutes, so less time is lost between runs."
}
```

Every `trf_or`-based key above (`ui.money_amount`, `ui.kp_amount`, `ui.mult_value`,
`ui.dur_*`, `ui.ok`, `ui.buy_mult_*`) has a symbol-only code fallback, so the HUD stays
presentable even before the merge; the rest render as their key name until merged (per
contract that is fine during the build).

## Module-internal conventions

- No `class_name` anywhere; sibling scripts are preloaded, except in `hud.gd`, which
  `load()`s its panels at runtime: hud.gd itself references no autoloads, so `--check-only`
  would otherwise fully compile preloaded dependencies and report their (normally filtered)
  autoload identifiers as one hard "Failed to compile depended scripts" error.
- `ui_util.gd` statics never name autoload identifiers — they resolve autoloads through
  `Engine.get_main_loop()` — which keeps them check-only-clean and hermetically testable.
- **`set_anchors_preset` is never called on a control already inside the tree**: with
  `keep_offsets=false` it rewrites offsets to preserve the current (usually 0×0) rect and
  silently collapses full-rect layers. Use `UiUtil.anchor_box`/`full_rect` instead.
- Motion (coach slide, hot-button pulse, toast pop, offline count-up) all check
  `SettingsService.reduce_motion` at trigger time.

## Simple mode + onboarding + orders (2026-08-30)

New in this pass: the simple-mode default face, the first-run onboarding overlay, and the
rush-order widget. New files: `onboard_targets.gd` (pure registry), `onboarding.gd`,
`order_widget.gd`; touched: `hud.gd`, `station_panel.gd`, `station_card.gd`, `top_bar.gd`,
`right_panel.gd`, `coach.gd`, `tooltip.gd`, `ui_util.gd`, `ui_theme.gd`, `tests/test_ui.gd`.

### Simple mode (default)

- `SettingsService.ui_mode` resolves through `UiUtil.resolve_ui_mode(v)`: only the exact
  string `"advanced"` counts, anything else (missing field included) is `"simple"`.
- Simple cards: glyph + name + throughput + WIP bar; quality block and the 4-button grid
  hidden; buy-multiplier row hidden too (bulk-buy is an advanced concern; FIX IT always
  buys exactly one step sim-side). Locked cards keep their big Unlock button.
- The current bottleneck's card is promoted (`CardPanelBottleneck` variation: 2 px amber
  edge, taller v-margins) and carries the FIX IT button (`FixButton` variation, ≥ 56 px,
  full width): label `ui.fix_it`/`ui.fix_unlock` (`ui.fix_saving` + disabled when not
  affordable) formatted with the cost, plus the view's localized `label` as line 2.
  StationPanel fetches `Game.get_best_fix_view()` once per sim_stats tick (simple mode
  only) and passes it to the bottleneck card; `{}` hides the button (nothing helps /
  everything maxed / API absent). Click → `Game.apply_best_fix()` + `Juice.squash` +
  AudioDirector `click` (`error` on a refused fix).
- Mode toggle (`GhostButton`, ≥ 44 px, top of the station panel) names the mode you switch
  TO (`ui.advanced_toggle`/`ui.simple_toggle`). Write path: `UiUtil.write_setting(key, v)`
  → set_setting/set_value/property **only when the field exists on the service**; when it
  returns false the panel self-emits `settings_changed("ui_mode", v)` so the flip still
  works session-locally (settings_panel stub-era precedent). All listeners react to
  `settings_changed("ui_mode", value)` **using the announced value**, not a re-read —
  that keeps the stub-era path coherent. TopBar bumps the money numeral to 26 px in
  simple mode (override removed in advanced). Selection (amber `CardPanelSelected`) wins
  over promotion styling.

### Onboarding overlay + target registry

- `onboard_targets.gd`: tiny named-rect registry (`register(name, Callable) / rect(name)
  -> Rect2` — zero rect = missing). One instance built by hud.gd and handed to panels via
  `setup(...)`. Registered: `top_bar_money` (top_bar), `coach` (coach — synthetic rect at
  its anchor while the panel is hidden/suppressed), `bottleneck_card` + `fix_button`
  (station_panel, re-resolved per call so the moving bottleneck stays tracked),
  `skills_tab` (right_panel, tab 0), `world_bottleneck` (hud itself: a box centered in
  the 3D gap between the panels). Providers must tolerate any-frame calls and return
  `Rect2()` when hidden.
- `onboarding.gd` starts on `load_completed` when `SettingsService.onboarding_done` is
  falsy AND `Data.db.onboarding` has steps (accepts the loader's normalized Array shape
  and the raw `{steps:[...]}` doc shape). Dim = root `_draw` of the four side rects
  around the hole (`side_rects` static, tested) + corner-notch polygons + amber
  `draw_style_box` ring — no shaders. Input: four blocker Controls (STOP) cover exactly
  the dim rects, so **the hole lets clicks through** (required: the FIX IT step advances
  by really buying). Steps with `advance == "on_upgrade"` hide Next and auto-advance on
  `EventBus.station_upgraded` (exactly as pinned — an unlock does not advance them; Skip
  covers that corner). Never soft-locks: Skip always visible (≥ 44 px), Esc (`ui_cancel`)
  skips, missing target ⇒ no hole (full dim) + centered bubble. Skip/finish writes
  `onboarding_done = true` via the guarded write; `_ran` also blocks re-trigger within
  the session. Spotlight repositioning is exp-smoothed, snapped under reduce-motion.
- While the overlay is up hud.gd relays its `active_changed(bool)` to
  `coach.set_suppressed()` (no hint evaluation/board) and `tooltip.set_suppressed()`
  (the tooltip layer sits above the dim, so it must stay dark). Both release on finish.

### Rush-order widget

- `order_widget.gd`, placed by hud.gd under the coach (top-center, `content_top + 64`).
  Hidden by default; state machine HIDDEN→ACTIVE→LEAVING survives `game_reset` (hides).
- Shows on `order_started` (slide-in; instant under reduce-motion). Renders from the
  `"order"` dict in each sim_stats snapshot, polling `Game.get_order_view()` as fallback
  when the snapshot lacks it; a snapshot with a non-empty order while HIDDEN re-shows
  instantly (loading into a running order). Fields: `ui.order_title` + localized name
  (`name`, falling back to `L.t(name_key)`), progress bar + `ui.order_progress`,
  `ui.order_time_left` (ceil, red under 10 s), `ui.order_reward`.
- `order_completed` → one toast `ui.order_done` with the BigNum reward (format-mode
  aware) + green flash (`OrderPanelGood`) + slide out; `order_failed` → `ui.order_missed`
  toast + slide out. Duplicate/stale signals ignored (state + id guard); under
  reduce-motion the flash is held as a color state, hide is instant.

### Guarded assumptions → observed landing

Everything above was written against guards and degraded gracefully; **during this session
the sim/save/data agents landed the real APIs** and all paths were runtime-verified against
them: `SettingsService.ui_mode`/`onboarding_done` (set_setting round-trip + disk persistence
observed across probe runs), `Game.get_best_fix_view()/apply_best_fix()` (a real FIX IT
click bought "Faster Machine" for $3 and charged the money), `Game.get_order_view()` and
the localized snapshot `"order"`, `Data.db.onboarding` (loader ships a plain Array of
normalized steps — the UI accepts both that and `{steps:[...]}`). Locale keys `ui.fix_*`,
`ui.order_*`, `ui.next/skip/done`, `ui.*_toggle`, `onboarding.step1..6` are all merged.
A 63-check headless probe (HUD against live autoloads) passed 63/63: onboarding first-run
flow incl. on_upgrade auto-advance and once-per-session, suppression/release, simple/advanced
round-trip, FIX IT label states, order lifecycle incl. duplicate-signal guards.

### Validation (this pass)

- All 18 `src/ui/*.gd` files pass the §2 filtered check-only with empty output.
- Full suite: **155 passed / 0 failed, 1717 asserts** (tests/test_ui.gd now 15 tests —
  new hermetic coverage: ui-mode resolution, fix-label keys, order ratio/countdown/progress
  formatting, onboarding step normalization + flow logic + side-rect tiling, target
  registry, new theme variations).
- `BNK_SMOKE=1` boot (fresh profile, onboarding overlay live): `BNK_SMOKE_OK`, zero
  script errors.

## Validation status (at hand-off)

- All 15 `src/ui/*.gd` files pass the §2 check-only command with **empty** output.
- Full suite: **125 passed / 0 failed, 1376 asserts** (includes `tests/test_ui.gd`: 7 tests,
  50 asserts — hermetic: coach evaluator/picker, formatting, status glyphs, theme build).
- Full boot (`BNK_SMOKE=1`): `BNK_SMOKE_OK`, **zero script errors** with the real sim, data,
  save and steam modules live. The HUD also boots cleanly against all-stub autoloads and
  even when `Game` fails to compile entirely (observed mid-edit), exercising every
  degradation path.
- Runtime-verified interactions (headless probes): 51 skill nodes laid out from the real
  skill_tree.json; all four tabs cycle; settings sliders + number-format write path; a real
  upgrade purchase through a card button (money charged, level text refreshed at 10 Hz);
  locked card exposes only its Unlock button; a live coach hint appeared from hints.json;
  offline popup and toasts render on their signals.
- Layout verified by dumping global rects: top bar 8..64 full width; left panel 372 px,
  right panel 436 px, both from y = 72 to the bottom; coach centered at x = 0.5; overlay,
  toasts and tooltip layers full-rect. ~456 px of 3D stays visible at 1280×720;
  `canvas_items` stretch scales everything to 4K / Steam Deck 1280×800.
