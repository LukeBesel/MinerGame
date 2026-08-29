# Demo Scope — Steam Next Fest / itch.io

The demo is the funnel (`docs/RESEARCH.md` §4, Pricing & funnel notes). It should be the actual
first ~45 minutes of the real game, content-gated rather than a separately built slice — same
codebase, same feel, same balance — because that's both the cheapest way for a small team to keep
it honest and the only way the "your save carries over" promise below is actually true.

---

## Length & where it ends

**Cut point: the player's first Kaizen Event.** That's a deliberate, not arbitrary, boundary —
it's the game's own first real narrative beat (see `docs/DECISIONS.md`: prestige is reframed as
"sell the factory, buy a bigger one," never as a punishment), it's designed to land at
**25–50 minutes of active play** (`balance.json` → `pacing.first_prestige_target_minutes`,
targeting the middle of that window per `docs/RESEARCH.md` design rule 12), and it's a screen the
full game needs to render anyway — the demo just changes what happens after the player confirms
it once.

## What's playable

- **Stations:** Stamping Press, CNC Lathe, and Weld Cell start unlocked, exactly like the full
  game. Paint Booth is purchasable with in-run money, also exactly like the full game.
- **Skill tree:** rows 1–2 of all five branches (Flow, Reliability, Quality, Speed, People) are
  purchasable normally.
- **Lean tools:** whichever of the seven (SMED, 5S, Kanban, TPM, Poka-Yoke, Heijunka, Andon) gate
  in naturally within that ~45-minute window, gated the same way as the full game — by actually
  hitting the bottleneck each one solves, never by an artificial demo timer. Which specific tools
  that ends up being is a balance call, not a marketing one; don't hardcode a tool list into demo
  copy that final tuning might not match.
- **Offline progress, autosave, buy multiplier x1/x10/x100/MAX, the Coach/Andon board, the
  bottleneck-cleared moment** — all present, unmodified. The demo should feel like the real game,
  because it is the real game.

## What's visible but locked

- **Stations 5–6 (Assembly Cell, QA & Packout):** rendered on the line at their normal position —
  visible, present, silhouetted — but not purchasable in the demo even with sufficient money.
  Clicking one surfaces a small "Full version" tag instead of the normal unlock button. The point
  is to show the player there's more line ahead of them, not to hide it.
- **Skill tree rows 3+:** visible in their normal position in all five branches, greyed out, each
  carrying a small "Unlocks in the full game" pill instead of a cost. Prereq lines still draw
  normally up to the demo boundary, so the tree reads as "more of this" rather than "broken."
- Neither of these is a hard wall — they're a preview of scale, which is the honest sell for an
  idle game (the loop keeps going, and here's proof).

## Telemetry-free, by principle

No analytics SDK, no crash-reporter phone-home, no hidden usage tracking in the demo build —
full stop. This isn't a launch-day gap to fill in later; it's the same "no dark patterns" pillar
the whole game is built on (`docs/RESEARCH.md` design rule 17–18), extended to data collection.
**Trade-off worth naming out loud:** this means Next Fest funnel tuning has to lean on Steam's own
aggregate wishlist/conversion numbers and direct player feedback (Reddit threads, Steam reviews,
Discord if one exists) rather than granular in-demo event telemetry. That's an intentional
choice, not an oversight — flag it so nobody goes looking for a telemetry dashboard that was never
going to exist.

---

## End-of-demo screen: "Wishlist to keep improving"

Fires once, the moment the player confirms their first Kaizen Event. It is a **screen, not a
wall** — always dismissible, and it does not reappear uninvited for the rest of that session
(a small persistent "Wishlist" button can stay available in a corner of the HUD afterward so the
option is never more than one click away, without nagging).

**Layout:** full-screen overlay, factory floor dimmed/blurred behind it — the same modal
treatment as the in-game Kaizen Event panel itself (continuity with `screenshots_plan.md` shot 3),
dark panel (`#1E2126`) on the near-black background (`#17191D`), amber (`#F4B942`) primary button.
A small "FREE DEMO" pill in a corner signals this is intentional, not a bug or a paywall.

**Copy:**

> **You found it. You fixed it. That's one Kaizen Event down.**
>
> In this run: **[N] parts made · [N] bottlenecks cleared · [$N] earned · [time] played.**
>
> This demo covers the first Kaizen Event. The real game keeps going — two more stations, three
> more rows of the skill tree, six more lean tools' worth of problems to go find.
>
> **[ Wishlist Bottleneck on Steam ]** *(primary button)*
>
> [ Keep playing this factory ] *(secondary, smaller — dismisses the overlay; the player can keep
> running the same demo-capped line indefinitely, nothing further unlocks, no timer, no nagging)*

**Note:** the bracketed stats pull from existing sim state (lifetime parts, bottleneck-cleared
count, money, time played are all already tracked per `docs/ARCHITECTURE.md` §6's `sim_stats`
snapshot) — this screen needs no new tracking to build, just a new UI state and a demo-build flag
to gate content, which is not yet implemented (see `INTEGRATION_NOTES.md`).

---

## Save carry-over promise

**The promise:** progress made in the demo isn't wasted if you buy the full game.

**How it's actually meant to work:** the save layer already defines an export/import string
format (`"BNK1." + base64(JSON)`, `docs/ARCHITECTURE.md` §9) specifically for portability. As
long as the demo and the full Steam build share the same save schema version and app identity,
"export your demo save, import it into the full game" is nearly free — it's the same mechanism
already planned for normal save backup/transfer, not a bespoke demo feature. **This is a promise,
not a confirmed implementation yet** — flagged explicitly in `INTEGRATION_NOTES.md`, since it
depends on the save module keeping demo and full builds on one unified schema rather than
diverging.

## Keep the demo alive after Next Fest

Per `docs/RESEARCH.md` §4: pulling a demo down right after Next Fest ends is a measurable
mistake — keeping it live correlates with **20–30% more wishlists** gathered in the run-up to
launch versus removing it. Default assumption for `launch_checklist.md`: the itch.io demo and the
Steam demo build both stay up continuously from first publish through launch day, not just during
the Next Fest window itself.
