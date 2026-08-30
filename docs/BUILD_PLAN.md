# Multi-Agent Build Plan

How this project is built by parallel agents in one pass, per the "send out multiple agents to
fully build this at the same time" instruction. File ownership is strictly partitioned so agents
never touch the same file; `docs/ARCHITECTURE.md` is the frozen contract they all code against.

## Wave 0 — Foundation (integrator, done first)
Repo, branch, Godot 4.5 project, autoload skeleton, EventBus, locale table, **BigNum with a
passing headless test suite**, test framework + runner, architecture contract, this plan.
A research agent runs concurrently → `docs/RESEARCH.md` (Mine Mogul / Idle Miner Tycoon,
Satisfactory, incremental pacing norms, Steam idle market, 3D idle comps).

## Wave 1 — Seven parallel build agents

| Agent | Owns | Builds |
|---|---|---|
| **SIM** | `src/sim/`, `src/core/game.gd`, most of `tests/` | SimEngine (stations/buffers/bottleneck/OEE), upgrades + bulk-buy math, skill effects, milestones, prestige, offline calc, Game bridge, autoplayer + pacing tests |
| **DATA** | `src/data/` | stations, 40–60-node skill tree, milestones, 25–35 achievements, balance knobs, coach hints, full locale table, loader + validation + data tests |
| **WORLD** | `src/world/` | 3D factory (Forward+ lighting, emissive low-poly machines built from primitives), conveyors with moving parts, WIP piles, scrap bins, status beacons + icons, orbit camera, first-person Gemba Walk, bottleneck-cleared 3D moment |
| **UI** | `src/ui/` | HUD top bar, station cards + buy x1/x10/x100/MAX, skill tree / Kaizen / stats / settings tabs, tooltips, Coach (Andon board), offline popup, toasts |
| **SAVE/STEAM** | `src/save/`, `src/steam/`, `steam/`, build + CI files | Autosave rotation ×3, versioned migration, export/import string, settings service, SteamBridge no-op wrapper, achievements hookup, export presets, build.sh/ps1, VDF templates, GitHub Actions CI |
| **JUICE** | `src/juice/`, `assets/audio/`, `tools/gen_audio.py` | Audio buses + generated SFX + layered ambience, purchase squash/burst/float-text, tweened count-up, slow-mo, screen shake (opt-in), reduce-motion support |
| **MARKETING** | `marketing/` | Store copy, capsule art briefs, 5 screenshot scenarios, 30 s trailer script, Next Fest demo scope, launch checklist, Steamworks achievement paste-list |

Rules of engagement: no git, no files outside ownership, no editor/`--import`, code to the
contract, log cross-module needs in `<dir>/INTEGRATION_NOTES.md`.

## Wave 2 — Integration (integrator)
Read all INTEGRATION_NOTES, reconcile API drift, wire `main.tscn`, run the full test suite +
boot smoke (`BNK_SMOKE=1`), run the autoplayer pacing test and adjust `balance.json` toward a
30–45 min first prestige, update CHANGELOG/KNOWN_ISSUES/README, commit, push, open draft PR.

## Post-plan (not in this pass)
Real playtesting, art/audio replacement passes, GodotSteam binary integration + real app ID,
Steam Deck hardware verification, second product line / supplier / customer content, export
template caching in CI, localization beyond English.
