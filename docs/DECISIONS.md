# Design & Engineering Decisions

Running log of decisions the design brief did not fully specify. Each is overridable — say the
word and we change it. Newest at the bottom of each section.

## Phase 0 / foundation

- DECISION: **GDScript over C#.** Godot 4.x C# cannot export to HTML5/web, and the itch.io
  browser demo is a hard funnel requirement; GDScript exports everywhere from one codebase.
  GodotSteam's GDExtension is also friction-free from GDScript. Tradeoff: weaker refactoring
  tooling and raw speed than C# — mitigated by a pure, data-driven sim (10 Hz, ~6 stations)
  that measures in microseconds; hot loops can move to a GDExtension later if ever needed.
- DECISION: **Godot 4.5 stable** pinned (binary verified in CI and locally).
- DECISION: Renderer **Forward+ on desktop, gl_compatibility on web** from one project
  (SSAO/glow degrade gracefully on web).
- DECISION: **3D factory floor** reconciles the brief's single-screen 2D UI (§7) with the
  request for "good graphics and a 3D world you walk around in": the game is fully playable
  from a mouse-only **orbit management camera** (the idle game), and a first-person
  **"Gemba Walk" mode** (Tab) lets you walk the line — thematically on the nose: lean's Gemba
  walk means "go see the real place of work". HUD panels overlay the 3D viewport per §7.
- DECISION: Added `/src/world` (3D layer) and `/src/core` (boot, event bus, locale, input) to
  the mandated folder layout.
- DECISION: Input actions registered **in code** (`input_setup.gd`), not hand-written into
  project.godot's brittle serialization format.
- DECISION: **No `class_name` anywhere; preload-const references** — the global class cache
  does not exist in headless/CI contexts and broke compilation. Verified workaround pinned in
  ARCHITECTURE.md §2.
- DECISION: Simulation is **deterministic expected-value math** (quality/uptime as continuous
  yields, no RNG in outcomes); randomness is cosmetic-only in world/juice. Makes every number
  unit-testable and the autoplayer reproducible.
- DECISION: Buffers have a **cap + blocking** (WIP piles before the bottleneck, stations
  BLOCKED when downstream is full, STARVED when input is empty) — readable constraint physics
  without WIP holding costs at launch.
- DECISION: Changeover time derates availability as `1 − changeover_time / changeover_period`
  (period in balance.json), so SMED upgrades produce immediately visible throughput gains.
- DECISION: **Skill tree + Kaizen Points persist through Kaizen Events** (prestige resets
  stations/money/WIP only). Prestige that "feels like starting over" is the #1 community
  complaint found in research.
- DECISION: Placeholder SFX are **procedurally generated WAVs** (committed, CC0) — no licensed
  audio in the repo; swap for real sound design later. No music tracks in this slice (slider
  still wired).
- DECISION: The brief's phase gates (stop and wait between phases) were **collapsed into one
  parallel multi-agent build** per the explicit instruction to "send out multiple agents to
  fully build this at the same time". Phase summaries are reported together at the end.
- DECISION: Product fiction: the line makes **"gizmos"** through Stamping Press → CNC Lathe →
  Weld Cell → Paint Booth → Assembly Cell → QA & Packout (6 stations, first 3 unlocked).

## Build/integration phase (module agents + integrator)

- DECISION: **Value-add pricing enabled** (`balance.value_add_pricing: true`): parts sell at
  `price_per_part × price_mults × unlocked_station_count`. Under contract-literal flat pricing,
  unlocking a quality<1 station strictly reduced revenue — a trap purchase violating pillar #1.
  The sim agent flagged it and recommended value-add; the data agent had already balanced
  unlock costs for it. Implemented as a data knob so the sim's hermetic fixtures still exercise
  flat pricing; the unlock-value estimator accounts for the (k+1)-station price bump.
  Measured after the switch: first prestige 28.6 min (target 25–50), suite 126/0.
- DECISION: Boot instances world+HUD **before** the save load — `SaveManager.boot_load()` emits
  `offline_report` synchronously and the popup must already be subscribed.
- DECISION (sim): `can_prestige` additionally requires `cip_gain ≥ 1` — no zero-gain resets.
- DECISION (sim): Station unlocks are strictly sequential (the line is linear).
- DECISION (sim): Prestige flushes buffer WIP (fiction: you sold the plant); conservation
  tracking stays exact via a `wip_flushed` counter.
- DECISION (sim): Achievements are evaluated inside the sim with the same trigger vocabulary as
  milestones (additive `achievement_unlocked` event).
- DECISION (juice): Ambience loops are 16 kHz mono (band-limited hum; 44.1 kHz couldn't fit a
  4 s seamless loop in the 150 KB per-file budget). One-shots stay 44.1 kHz.
- DECISION (world): In Gemba Walk, Esc exits walk mode (consumed); a future pause menu opens on
  a second Esc. No initial `camera_mode_changed` at boot — HUD assumes orbit.
