# Bottleneck

A lean-manufacturing incremental/idle factory game (working title). You inherit a struggling
factory with one hand-cranked machine; find the bottleneck, fix it, and grow into a lean,
automated plant that runs itself — Theory of Constraints as a game loop, on a 3D factory floor
you can walk (Gemba Walk mode). Steam first ($4.99), itch.io web demo as the funnel.

**Stack:** Godot 4.5 stable · GDScript · JSON data-driven balance · headless test suite.

## Run

Open the project in Godot 4.5 and press Play, or headless smoke:

```bash
BNK_SMOKE=1 godot --headless --path .
```

## Tests

```bash
godot --headless --path . -s res://tests/run_tests.gd
# filter: BNK_TEST_FILTER=bignum godot --headless --path . -s res://tests/run_tests.gd
```

## Repo map

- `src/sim` — pure simulation (no nodes, no autoloads, unit-tested)
- `src/data` — all tunables: stations, skill tree, milestones, achievements, balance, locale
- `src/world` — 3D factory, cameras (orbit + first-person Gemba Walk)
- `src/ui` — HUD, panels, tooltips, Coach/Andon board
- `src/juice` — audio, particles, tweens, screen feel
- `src/save` — autosave rotation, migrations, offline progress, settings
- `src/steam` — GodotSteam wrapper (safe no-op without Steam)
- `tests` — headless tests + autoplayer balance tool
- `docs` — ARCHITECTURE (the contract), DECISIONS, BUILD_PLAN, RESEARCH
- `marketing` — store copy, capsule briefs, trailer script, launch checklist
- `steam/`, `build.sh`, `build.ps1` — export + Steam content builder pipeline

## Working rules

Read `docs/ARCHITECTURE.md` before writing code — it is the binding contract (module
ownership, EventBus registry, sim API, data schemas, headless GDScript gotchas).
