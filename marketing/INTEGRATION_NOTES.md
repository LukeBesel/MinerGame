## Marketing module — integration notes

Grounded in `docs/RESEARCH.md`, `docs/ARCHITECTURE.md` (§14 palette + game overview, and the
data/sim/EventBus contracts referenced throughout), `docs/DECISIONS.md`, `docs/BUILD_PLAN.md`,
and `README.md`. No files touched outside `marketing/`.

### File inventory

| File | Contents |
|---|---|
| `marketing/store_page.md` | Steam short description (2 variants, both under the 300-char limit), long description with idle-fan-first feature bullets, About This Game narrative, itch.io tagline + demo blurb. |
| `marketing/capsule_briefs.md` | Shared art direction + palette (sourced from ARCHITECTURE §14) + title/logo treatment, then per-size composition/crop/text-safe guidance for header, small, main, vertical, page background/hero (+ ultra-wide variant), both library sizes, and the transparent logo; closes with a 4-point readability checklist. |
| `marketing/screenshots_plan.md` | Five staged scenarios (hour 0, hour 1, first Kaizen Event, mid-game, late-game Gemba Walk) with camera/on-screen/HUD-state staging instructions and a caption per shot. All stat figures marked explicitly as illustrative, not spec. |
| `marketing/trailer_script.md` | 30-second shot-by-shot script (cold open → upgrade montage → whack-a-mole tension → the bottleneck-cleared peak at 0:18 → payoff montage → title card/CTA), timecoded with music/SFX cues using the game's actual pinned SFX names, plus 3 differently-targeted 15-second cutdown variants. |
| `marketing/demo_scope.md` | Next Fest/itch demo cut: scope (first ~45 min, ends at first Kaizen Event), what's playable vs. visible-but-locked, the end-of-demo "wishlist to keep improving" screen (full copy + layout spec), the save carry-over promise and its technical basis, and the telemetry-free stance. |
| `marketing/launch_checklist.md` | T-minus relative timeline from itch demo through second-product-line beat; full r/incremental_games post draft (title + 151-word body) and a manufacturing/ops subreddit draft with subreddit self-promo cautions; 10-week devlog cadence table; price/discount policy; post-launch content beat sequencing. |
| `marketing/steamworks_achievements.md` | Explains the file is auto-fillable from `src/data/achievements.json` once it exists, specs the 3-column Steamworks paste format, and gives 6 example rows (spanning 6 distinct trigger types) plus a voice guide for whoever fills the remaining ~19–29. |
| `marketing/INTEGRATION_NOTES.md` | This file. |

### Claims that depend on features shipping (flag each before external use)

1. **"Bottleneck" is a working title**, per the task brief and `README.md`/`ARCHITECTURE.md`.
   Every file here uses it as if final — it's the highest-blast-radius dependency in this whole
   set. If the title changes, every file needs a pass: store copy, the capsule wordmark spec,
   the trailer title card, both Reddit post drafts, the demo's end screen copy.
2. **"No comp lets you walk your own factory floor"** (store page, trailer, r/incremental_games
   draft) is grounded in `docs/RESEARCH.md`'s comp survey, but that survey has a scope and a
   cutoff, and RESEARCH.md itself calls Gemba Walk "the single highest execution-risk feature in
   the whole design." If it slips scope, ships thin, or a comp surfaces later, soften or drop
   this claim before it goes out publicly — don't let it stand unchecked through launch.
3. **Steam Deck language** is deliberately written as "planned" / "real controller input for both
   camera modes," never "Verified" — because it isn't yet. Update to the actual achieved badge
   tier once Valve's certification runs, and not before.
4. **First-Kaizen-Event / first-prestige timing** ("~45 minutes," "30–45 minutes") is a pacing
   *target* in `balance.json` (`pacing.first_prestige_target_minutes`), only real once
   `tests/test_pacing.gd`'s autoplayer run actually confirms it. Re-check every runtime figure in
   `demo_scope.md` and the store/launch copy against that passing test before external use.
5. **Demo save carry-over to the full game** (`demo_scope.md`) is a promise that depends on the
   save module deliberately keeping demo and full-game builds on one unified save schema and app
   identity. It is not yet an implemented or confirmed decision — this is the single most
   concrete "please build this" ask in the whole marketing set, and it needs an explicit yes from
   whoever owns `src/save/` before the promise ships anywhere public.
6. **`steamworks_achievements.md`** ships only 6 example rows in-voice; the real 25–35-row table
   depends entirely on `src/data/achievements.json`, which doesn't exist yet (confirmed: as of
   this pass, `src/data/` holds only a stub `loader.gd`). Needs a full pass once that file lands.
7. **Achievement icon art** (achieved/unachieved image pairs) isn't produced by this module and
   isn't clearly owned by any module in `ARCHITECTURE.md`'s table either — flagging a real gap,
   not just a marketing dependency.
8. **`$4.99 → $6.99` price increase timing** (`launch_checklist.md`) is tied to an assumed
   post-launch content cadence (supplier/customer systems, second product line) that's real
   roadmap per `docs/BUILD_PLAN.md`'s "Post-plan" section, but the *timing* (T+6, T+9–12 months)
   is my estimate, not a commitment — reconfirm against actual post-launch velocity.
9. **`steam/steam.json`'s `app_id` is currently the placeholder value (480, Valve's own public
   test AppID)** — nothing in this marketing set is wired to a real store URL or AppID.
   `launch_checklist.md`'s "store page live" step assumes a real AppID has already been
   provisioned through Steamworks (a real-world admin/business step, outside this module's lane).
10. **Trailer capture is blocked on integration, not just art.** `trailer_script.md` calls for
    clean footage of systems (the bottleneck-cleared slow-mo/green-wave/chime, Gemba Walk, the
    Kaizen Event panel, a populated skill tree) that are being built by other agents in this same
    wave. Capturing the mid-game and late-game beats specifically will likely need some way to
    fast-forward a save into that state (autoplayer or a dev console) rather than playing there
    live — worth flagging to whoever owns that tooling.
11. **Named lean tools aren't yet mapped to real skill-tree branches or nodes** —
    `skill_tree.json` doesn't exist yet either. Nothing here claims a specific branch mapping,
    but once it ships, spot-check that SMED/5S/Kanban/TPM/Poka-Yoke/Heijunka/Andon all actually
    appear somewhere in the real 40–60 node set before repeating them as a fixed list externally.
12. **Next Fest dates are deliberately left relative** (historical Feb/June/Oct cadence noted,
    no specific date asserted) — substitute real confirmed dates from Steamworks before treating
    `launch_checklist.md`'s T-markers as a real schedule.

### The one thing to A/B on the store page

**The header capsule's hero image** — not the short description text. Header capsule is the one
image that shows up everywhere (search results, tag browsing, recommendations), Steam explicitly
supports testing multiple capsule images against each other pre-launch, and `docs/RESEARCH.md`
§4 notes idle/incremental is the single most-entered tag at Next Fest — meaning the highest
competition for exactly this first glance, where a fraction of a second decides whether someone
even reads the description at all.

Test two honest variants of the same hero scene, not two different messages: **(A)** the
red-machine-among-green-machines composition specified as the default in `capsule_briefs.md`
(the Theory-of-Constraints hook — broad, needs no explanation, but looks similar in silhouette to
other factory/automation games at a glance), versus **(B)** a Gemba Walk first-person shot as the
hero image (the thing no comp has — more distinctive, but reads as "3D factory game" first and
needs the description to do more work to land the idle-game pitch). Whichever wins tells the team
something concrete about this specific audience that no amount of internal debate will: whether
the ToC hook or the walkability hook is doing more of the actual converting, which should then
also settle which one leads the trailer's cold open and the short description's opening line.
