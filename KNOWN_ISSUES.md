# Known Issues

Updated every phase. See docs/DECISIONS.md for intentional scope calls.

## Needs hardware / real-environment verification
- **Forward+ visual pass pending**: glow/SSAO/fog were composed via software-GL captures
  (gl_compatibility). Eyeball bloom strength, SSAO contact shading, and fog density once on a
  real GPU in the editor.
- ~~Web build untested in a real browser~~ **Done**: exported (no-threads, gl_compatibility)
  and verified in Chromium via Playwright — boots clean (zero console errors), sim runs,
  purchases/toasts/tooltips/coach work, Tab enters Gemba Walk. Found and fixed three bugs in
  the process (Tab vs. ui_focus_next, parked-cursor edge-pan drift, freed-node juice callable).
- **Steam Deck**: focus navigation and 36 px targets are implemented, but no hardware pass; no
  gamepad button bindings yet (keyboard+mouse fully playable; controller is Phase-4-quality
  work, checklist in steam/README.md §3).
- **Export templates not installed in CI** — the test+smoke jobs run on every push; the export
  job is documented and manual until templates are cached (they're ~1 GB).

## Steam integration is scaffolded, not live
- GodotSteam GDExtension is **not vendored**; `SteamBridge` is a verified no-op with four
  `TODO(real GodotSteam)` blocks, and `src/data/steam.json` carries Valve's 480 placeholder id.
- Steam Cloud conflict flow exists as a tested pure decision function + documented prompt copy
  (steam/README.md), but is not wired into boot — needs a real Steam session.

## Design/content gaps (deliberate for this slice)
- No pause menu (Esc in walk mode exits walk; second Esc currently does nothing).
- Music slider is wired but no music tracks ship — ambience layers only.
- Second product line, supplier, customer-with-quality-demands, parallel lines, and the
  "world class plant" ending are prestige-tier content not yet built (Phase 5 scope).
- The greedy autoplayer never buys station unlocks (it rejects the temporary throughput dip),
  so unlock pacing (paint ~4–6 min, assembly ~12–16, pack ~25–35) is model-estimated for a
  human player, not autoplayer-enforced. First-prestige timing IS autoplayer-enforced in CI.
- `ACH_ZERO_SCRAP_HOUR` requires driving quality to exactly 1.0 via deep tooling+skill
  investment — reachable but punishing; revisit after playtests.
- Localization runs through the custom `L` table; swap to Godot's TranslationServer when a
  second language lands.

## Minor
- `--check-only` cannot resolve autoload identifiers (documented filter in ARCHITECTURE §2);
  scripts that preload autoload scripts surface one extra residual line (see
  src/save/INTEGRATION_NOTES.md).
- More than ~7 stations would outgrow the factory shell — bump `FLOOR_MAX_X` in
  `src/world/world_lib.gd` when the line grows.
