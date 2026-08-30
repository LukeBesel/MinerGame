# Trailer Script — 30 Seconds

Cold open on a problem → the feel of fixing things → the peak moment the whole genre is built
around → proof it was worth it → ask. SFX cues below use the game's actual pinned sound names
(`docs/ARCHITECTURE.md` §11: `click, buy_small, buy_big, unlock, chime_clear, milestone,
prestige, scrap, error, tab`) so the editor can cut straight to the shipped audio library instead
of commissioning new sound — `chime_clear` is *literally* the bottleneck-cleared cue the game
already plays at this exact moment, so the trailer's emotional peak and the game's own signature
moment are the same sound.

---

## Full cut (0:00–0:30)

| Time | Shot | Camera / action | Music & SFX | On-screen text |
|---|---|---|---|---|
| **0:00–0:04** | Cold open | Extreme close-up on a single struggling machine. Pulsing red-orange bottleneck beacon, mechanical clunk/grind on every cycle, visibly straining. Hold static — let it be uncomfortable. | Low tense drone begins under raw mechanical SFX (clunk, grind, strained servo whine). No music yet. | *(none — let the red glow and the sound sell the problem before any text does)* |
| **0:04–0:10** | Quick-cut upgrade montage | Rapid cuts: cursor clicks a buy button → cost pays out → squash/burst + float-text juice → cut to a different station's upgrade → buy multiplier flicks x1 → x10 → conveyor visibly speeds up a notch after each purchase (every upgrade must be visibly, not just numerically, different — the QA rule the whole game is built on). 3–4 cuts, each faster than the last. | `click` / `buy_small` / `buy_big` used *as* the percussion — a rhythmic click-click-CHUNK pattern the music builds around. A driving beat enters under it, tempo climbing with each cut. | Three quick word-stamps, one per cut, on-beat: **"UPGRADE."** → **"UNLOCK."** → **"REPEAT."** |
| **0:10–0:17** | Rising tension — whack-a-mole | The first bottleneck resolves (brief flash) — and immediately a *different* station lights up red instead. Buffer visibly piling up in front of it. Quick insert: a skill-tree node lighting up on purchase, a Coach/Andon hint bubble flashing. Cuts get tighter and faster; camera pushes slightly closer each time. | Music keeps climbing — added layer, faster tempo. `unlock` sting on the skill-node insert. | Two fast text flashes, confident and unexplained: **"SMED. KANBAN. TPM."** → **"REAL LEAN TOOLS."** |
| **0:17–0:18** | The held breath | Music ducks hard, near-silence. Camera pushes tight on the new bottleneck's red beacon. A single purchase click lands. | Music drops to almost nothing. One clean `click`. | *(none — the silence is the beat)* |
| **0:18–0:21** | **THE BOTTLENECK-CLEARED MOMENT (peak)** | Cut wide enough to actually see it travel: slow-motion, the beacon flips red → green, and a green pulse wave visibly sweeps down the full conveyor line, station by station. This is the emotional center of the whole trailer — give it real space, no competing text. | `chime_clear` rings out clean over a triumphant musical swell/drop — the exact cue the shipped game plays at this exact moment (`EventBus.bottleneck_cleared`). | *(none — let it land clean)* |
| **0:21–0:26** | Payoff montage | Fast, satisfying cuts: the full six-station line running all-green at speed → a Kaizen Event flash (numbers resetting, multiplier climbing — recognizable as "prestige," not as loss) → cut into **first-person Gemba Walk**, walking down the humming, glowing line at ground level, warm practical lighting. | Music sustains at full, triumphant energy — the fullest mix of the trailer. Layered ambient factory hum under the beat. | **"PRESTIGE. FOREVER."** (on the Kaizen flash) then, timed to the Gemba Walk cut specifically: **"WALK YOUR OWN FACTORY."** |
| **0:26–0:30** | Title card + CTA | Cut to a clean dark card (`#17191D`) — wordmark lockup per `capsule_briefs.md` (chevron motif, red-orange beacon dot), tagline beneath, then the ask. | Music resolves to a final clean hit/tag; a faint ambient hum stays under the silence so it doesn't go dead. | **"BOTTLENECK"** → **"Find the bottleneck."** → **"Wishlist now — free demo on itch.io"** |

**Total runtime: 30 seconds exactly (4+6+7+1+3+5+4).**

---

## 15-second cutdown — variant list

Three variants, each trimmed to a different placement rather than uniformly compressed — cutting
every beat to half-length would flatten the one beat (0:18) that has to land clean.

### Variant A — "Idle-fan cut" (social ads, r/incremental_games-adjacent placements, general idle-tag audience)
Leads with the loop-clarity-and-payoff hook this audience responds to; drops the lean-term
callouts and Gemba Walk entirely to keep the runtime on the core idle loop.
1. 0:00–0:04 — Cold open (unchanged)
2. 0:04–0:07 — Upgrade montage, trimmed to 2 cuts ("UPGRADE." / "REPEAT.")
3. 0:07–0:10 — Bottleneck-cleared moment, compressed (slow-mo held shorter, `chime_clear` intact)
4. 0:10–0:13 — Payoff flash: full line running + Kaizen Event number climb only (cut Gemba Walk)
5. 0:13–0:15 — Title card + CTA (tight)

### Variant B — "Ops/lean cut" (manufacturing/ops subreddit posts, LinkedIn-adjacent shares)
Leads with vocabulary authenticity and the Gemba Walk callout specifically — the "this is
accurate *and* funny" hook this audience responds to per the brief.
1. 0:00–0:04 — Cold open (unchanged)
2. 0:04–0:08 — Upgrade montage kept short, but the **"SMED. KANBAN. TPM." / "REAL LEAN TOOLS."**
   text beat survives the cut intact — this line is the whole point for this audience
3. 0:08–0:11 — Bottleneck-cleared moment, compressed
4. 0:11–0:14 — Gemba Walk shot only (cut the prestige flash), with **"Gemba Walk: go see the
   real place of work."** as on-screen text — the actual lean meaning of the term, which this
   audience will recognize and appreciate
5. 0:14–0:15 — Title card + CTA (tight)

### Variant C — "Features-forward cut" (embedded on the Steam/itch store page itself)
For someone already on the store page — no need to "stop the scroll" with the cold open, so this
cut is denser with proof rather than hook.
1. 0:00–0:03 — Cold open, compressed to a flash rather than a held beat
2. 0:03–0:06 — Upgrade montage, 2 cuts
3. 0:06–0:09 — Bottleneck-cleared moment (unchanged — never compress this below ~3 seconds)
4. 0:09–0:13 — Full payoff montage: line running + Kaizen Event + a Gemba Walk flash, all three,
   fast
5. 0:13–0:15 — Title card + CTA
