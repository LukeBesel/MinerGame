# Changelog

## [Unreleased] — accessibility + content + art wave

- **Simple mode (new default)**: one glowing FIX IT button on the bottleneck buys the best
  fix; Advanced toggle restores full upgrade grids. First-run 5-step spotlight onboarding
  (skippable, one-time).
- **Rush Orders**: timed customer orders sized to your throughput — bonus payouts, zero
  failure penalty; widget with progress/countdown.
- **Art overhaul**: real CC0 PBR materials (ambientCG), AgX grading, all six machines
  rebuilt as detailed assemblies, dressed hall (pallets, racking, mezzanine, signage,
  decals), belt rails/rollers/part variants.
- Browser-verified end-to-end (Chromium): onboarding -> FIX IT purchase -> bottleneck
  cleared pulse; zero console errors. Suite 155/0 (1717 asserts).
- Hosted playable demo: webdemo/ served via raw.githack from this branch; GitHub Pages
  workflow activates on merge to main.

## [Unreleased] — full vertical slice (Phases 0–4 scope, parallel build)

### Phase 0 — Foundation
- Godot 4.5 project skeleton, autoload architecture, event bus, locale table, input actions.
- BigNum mantissa/exponent type (suffix + scientific formatting) with headless tests.
- Headless test framework + runner (zero-assert protection); architecture contract
  (`docs/ARCHITECTURE.md`); research brief; decision log; multi-agent build plan.

### Phase 1–3 — Core loop, depth, balance
- Pure simulation engine: fluid two-sweep line flow, buffers with STARVED/BLOCKED semantics,
  always-flagged bottleneck + cleared detection, continuous quality yield → scrap, rolling OEE,
  exact geometric bulk pricing with O(1) MAX-buy, full skill-effect and milestone/achievement
  trigger vocabularies, KP passive income, CI-manager auto-buyer, Kaizen Event prestige (CIP),
  closed-form offline progress (<50 ms for any duration).
- Value-add pricing (`balance.value_add_pricing`): sale price scales with unlocked station
  count, making line extension a real revenue decision.
- Data content: 6 stations × 4 upgrade tracks, 51-node lean skill tree across five branches,
  24 milestones, 30 achievements, 10 coach hints, 354-key English locale, validating loader.
- Balance tuned against the real engine via the greedy autoplayer: first prestige 28.6 min
  (target 25–50), 38+ distinct progress events in the first 15 minutes.

### Phase 2 — Feel
- 3D factory floor: composed industrial lighting (Forward+, degrades on web), six distinct
  machine silhouettes with cycle animations, chevron conveyors with riding parts, WIP piles,
  scrap bins, traveling bottleneck beacon with colorblind-safe icons.
- Signature bottleneck-cleared moment: slow-mo + green floor pulse + bell chime.
- Orbit management camera (mouse-complete) + first-person Gemba Walk mode (Tab).
- Generated CC0 SFX + three-layer ambient factory hum scaling with throughput; purchase
  squash/bursts/float text; tweened money count-up; optional screen shake; reduce-motion path.
- HUD: top bar, station cards with bottleneck-helper highlighting, buy x1/x10/x100/MAX,
  skill tree with prereq lines, Kaizen/stats/settings tabs, tooltips (hover/focus/long-press),
  Coach/Andon hint board, offline "While you were away" popup with count-up, toasts.

### Phase 4 — Steam readiness (scaffolded)
- Autosave every 30 s + on quit, 3 rotating backups, versioned migration machinery,
  base64 save export/import, corrupt-save fallback with player-facing toast.
- SteamBridge (clean no-op without Steam), achievements pipeline wired end-to-end,
  Steamworks paste list generated from data, VDF templates + steam/README runbook.
- Export presets (Windows/Linux/macOS/Web), build.sh/build.ps1, GitHub Actions CI running
  the full suite + a boot smoke on every push.
- Marketing package: store page copy, capsule art briefs, five screenshot scenarios,
  30-second trailer script, Next Fest demo scope, launch checklist.

### Test status
126 passed / 0 failed (1379 asserts) headless; CI green; autoplayer pacing gate enforced.
