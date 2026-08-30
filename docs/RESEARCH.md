# Bottleneck — Market & Design Research Brief

Research to inform balance and design decisions. Five topics, each with tight takeaways, followed by numbered design rules mapped to our five pillars, a "do not copy" list, and pricing/funnel notes for a $4.99 Steam launch.

---

## 1. "Mine Mogul" — idle mining tycoon comps

The literal Steam title is **MineMogul** (NoodleForge, Early Access Dec 2025, $14.99) — but it's a physics-based automation *builder*, not a classic idle/incremental game, so we also cover the two closest "idle mining tycoon" matches: **Idle Miner Tycoon** (Kolibri Games, mobile) and **Mr. Mine** (mobile). All three are covered below.

**MineMogul** (closest literal match, but a build-sim, not an idler):
- Underground factory sandbox: mine resources, buy machines, route conveyors through cave physics. "Overwhelmingly Positive," ~96% of 3,000+ reviews.
- Player feedback: satisfying early quests, but late-game becomes repetitive research-ticket grinding — "you make essentially the same machine layout four times" for the final quests.
- Cited gaps: no blueprints/copy-paste, cramped starter build space, sales bin disconnected from production zones, some machines buggy (stuck items on conveyors), no endgame content yet, no multiplayer.
- Physics simulation ("conveyors overflow, parts scatter") is charming in marketing but the same feature is blamed for performance struggles as factories scale — a direct cautionary tale for us.
- Priced at $14.99 because it sells build-depth, not idle pacing — reinforces that we must market Bottleneck as *idle*, not *automation builder*, to avoid attracting players who want MineMogul's freeform building.

**Idle Miner Tycoon** (the real "idle mining tycoon" — and structurally almost identical to our ToC pitch):
- Core loop is explicitly three linked stages — **Mine Shaft → Elevator → Warehouse** — each able to bottleneck the other two; leveling the weakest stage to match the others *is* the entire early game.
- Managers (unlocked once a shaft hits level 5) automate a stage; "Idle Cash" = offline earnings rate. This is Theory of Constraints as a mechanic, just never named as such — validates that our lean/ToC framing is teaching a mechanic players already find compelling unnamed.
- Kolibri's own postmortem ("8 Lessons") stresses: prototype bare-bones first (no art/IAP), show the whole loop with visible choke-points on one screen, and differentiate by inverting a known formula (they inverted tower-building into downward mining).
- Their D1 retention on the stripped prototype hit 63–81% vs. an industry baseline of ~40% — evidence that a legible core loop alone, before any art pass, is what proves a design works.
- Monetization is 60% ads / 40% IAP, both selling "skip the wait" — the opposite of our no-dark-patterns pillar, but useful as the thing to explicitly reject.

**Mr. Mine** (mobile idle digger):
- Runs two simultaneous progress loops — surface profit funds better drills, while deeper mining yields rare items to sell — which is what reviewers cite as keeping it from feeling one-note.
- Layers on Super Miners, relics, research and an "Underground City" as depth reveals — new systems gate in as you go deeper, not all at once.
- Praised as hitting "a sweet spot between relaxing idle play and crunchy optimization" — a good north star for our tone.

---

## 2. Satisfactory — watching the line flow

**What makes it work:**
- Sound is load-bearing: machines snapping into place, the hum of equipment powering up, and tight, responsive placement controls make construction feel intentional — before any visual feedback registers.
- Machines give distinct audio+visual state changes at higher output — e.g. Production Amplifiers emit a low drone *and* a visible red/purple particle effect only while active, so a machine's state is legible from both channels at once.
- The loop is "observe current behavior → expand/redesign to fix it → watch it work" — the redesign itself, not just the payoff, is the fun.
- Conveyor belts are given deliberate height, distance and spectacle — routing is itself a visual centerpiece, not just plumbing.
- Progression removes stagnation: build for a tier → unlock the next tier's tools → produce newly-unlocked parts → repeat, continuously, with no dead stretches.

**What transfers to a small idle game:**
- Machine-state legible via *sound and light together* (hum layering, emissive glow tied to output/blocked state).
- A visible "snap"/confirmation cue on every placement or upgrade action.
- The redesign-and-watch loop, at a much smaller scale: change one machine, see the whole line's flow visibly respond.

**What does NOT transfer (see also "Do NOT copy" below):**
- Freeform belt-routing as a puzzle (splitters, mergers, undergrounds, verticality) — that puzzle *is* Satisfactory's whole genre; it's a complexity trap for a small idle game.
- The sheer scale ("the factory must grow" to literally thousands of items) and deep multi-tier tech trees.
- Large-scale freeform 3D base-building across an open world.

---

## 3. Incremental game pacing norms

- **Cookie Clicker's curve**: exponential building *cost* against near-fixed per-building *income* produces a roughly logarithmic feel — each additional order of magnitude of currency takes about the same real-time effort. Early game is deliberately low-intensity and payback-period-driven ("what pays for itself fastest"); it's designed to be a low-attention background game, not a high-engagement one.
- **Prestige math** (per Math-of-Idle-Games analysis): two families exist — *lifetime-based* curves (Cookie Clicker's cube-root: need ~8x prior progress to double your reset reward) and steeper *run-independent* curves (Egg, Inc.'s 1/7 exponent: need ~128x, which nudges players toward active play over idling). Neither is free — the choice sets whether resets reward patience or optimization.
- Successful designs use **"bumpy" pacing** — alternating faster and slower stretches rather than one smooth exponential — so a reset feels earned rather than arbitrary, and so the fun isn't purely "big numbers," which stops being novel on its own fairly fast.
- **Multiple production "clocks"** matched to different play styles keeps both tab-switchers (short cycles) and infrequent check-in players (long cycles) engaged at once, per idle-design analysis of games like Egg, Inc.
- **First-prestige timing** has no single magic number, but the consistent principle is: reset when the next milestone would take longer than restarting-and-recatching-up, commonly once progress has slowed to ~10–20% of peak speed. Real examples span from a first tool purchase in ~20 seconds up to a deliberately long ~120-minute first prestige — the "hook" window developers actually design around is the **first 0–30 minutes** of a session.
- **Consistently cited complaints** (from dev-community and player commentary): scroll/UI friction (having to scroll away from the shop to check status and back), idle games that don't actually progress fully in the background, "one true optimal strategy" grinds that don't reward adapting, unclear next-purchase guidance ("walls"), and — Melvor Idle's most-repeated specific complaint — being "borderline unplayable without a wiki tab open" because tooltips don't explain enough on their own.
- **Consistently cited praise**: real offline/AFK progress that doesn't punish stepping away, visible choke-point/bottleneck structure that tells you exactly what to upgrade (Idle Miner Tycoon), multiple simultaneous loops that layer in over time rather than dumping complexity at once (Mr. Mine), and steady content cadence in live titles (Idle Miner Tycoon has shipped 160+ weekly updates).

---

## 4. Steam idle-tag market

- **Price point**: $4.99 is a well-populated, proven price for the genre — **Cookie Clicker itself sells on Steam at $4.99** (Overwhelmingly Positive, ~90k+ reviews), and is our single closest direct comp. **Shelldiver** ($4.99, Overwhelmingly Positive, ranked among top incrementals) sits at the same price. **Increlution** ($3.99, "Very Positive," 85% of 1,230 reviews, ships a free demo) and **Nodebuster** ($2.99) bracket just below us.
- **The ceiling**: **Melvor Idle** ($9.99 base + paid content expansions) has grossed an estimated $6.7M lifetime — proof a premium idle game can be a real, sustained business — but that's a live-service-with-DLC model built over years, not a v1.0 launch comp.
- **Free-to-play alternative model**: **The Perfect Tower II** and **Idle Slayer** are both free (ad/IAP-supported) and very well reviewed (~85% and ~78–83% positive respectively) — useful as evidence the genre is crowded at $0 too, which argues for a distinct premium hook rather than competing on "more content, free."
- **Market context** (industry market-research aggregators, treat as directional not precise): the broader idle-games market is estimated around $14B in 2025 and growing double-digit annually; Steam's idle-tag specifically is described as a fast-growing, increasingly crowded indie category.
- **Next Fest funnel**: idle/incremental is reported as the single most-entered tag at Steam Next Fest — meaning highest competition for attention. General wishlist-to-buyer conversion benchmarks: below 5% signals a real problem, 10–20% is solid/typical, 12–17% is typical *during* Next Fest specifically, and 26–32% is excellent. Keeping a demo live *after* Next Fest ends correlates with 20–30% more wishlists gained before launch versus pulling it down.
- One widely-cited (if outlier) proof point: a solo-built idle game demo went from ~200 followers to ~20,000 Next Fest wishlists off a demo built in about two weeks — in this genre, a clear hook can outweigh production values.
- **Steam Deck**: idle games generally run fine on Deck (low system requirements, mostly UI-driven), but many skip controller support entirely and default to trackpad-only, so few earn full "Verified" status. There's a dedicated Deck-friendly audience for the genre (curated "Steam Idler Fest" sales exist). Because Bottleneck has both an orbit camera and a first-person walk mode, real controller support for both is achievable and would be rarer differentiation than most idle competitors bother with.

---

## 5. 3D idle/factory comps at small scope

- **Astro Colony**: a "3D Factorio" with fully destructible voxel planets and a mobile base that travels through a procedurally generated galaxy. Reviews are mixed: the moving-base concept is called novel, but critics say the automation itself is "neither the most streamlined nor the most satisfying" and "doesn't grasp what makes automation satisfying, even in a vacuum" — plus real performance issues and bugs. **Lesson: novel 3D presentation cannot substitute for flow-clarity fundamentals, and the destructible-voxel scope clearly overextended the team.**
- **shapez 2**: the strongest comp for flow-readability, even though it's orbit/top-down, not first-person. 1.0 launched April 2026 to "Overwhelmingly Positive" (97% of ~8,750 reviews). It expanded into 3-layer belts/platforms but kept legibility as the design priority: belts move at a consistent, readable pace; machines have "just enough motion to communicate what's happening" without noise; a linear "main bus" layout means "you can walk the bus until you find the stalled building." **This is our best available model for how to keep a factory line readable at a glance.**
- **MineMogul** (see §1): physics-simulated parts on conveyors look charming in trailers but are the cited cause of both performance problems at scale and stuck-item bugs — a direct warning against simulating physical parts in our own conveyor system, especially for a browser-exported itch.io demo.
- **Low-poly + emissive lighting is the proven achievable art direction for small teams**: "lighting is your best texture" — directional light and emissive materials communicate machine state and quality far more cheaply than high-poly detail or texture work, and keep both WebGL export performance and Steam Deck performance realistic. Established examples (Polytopia, Superflight) show this reads as a deliberate style, not "cheap," when lighting is used with intent.
- **No comp we found combines idle/incremental pacing with a genuinely walkable first-person 3D factory floor at small scope.** That's real white space for Bottleneck's Gemba Walk mode — and, per the Astro Colony lesson above, also the single highest execution-risk feature in the whole design, since 3D doesn't automatically make anything more satisfying.

---

## Design rules we adopt

### Pillar 1 — always one obvious next step (bottleneck glows red)
1. Ship a native, always-on "Bottleneck mod" equivalent (the single most popular third-party Factorio QoL mod is exactly this): every machine shows a green/amber/red state — running / starved-input / blocked-output — and the single worst constraint on the whole line gets a persistent red glow plus a findable ping, visible from the orbit camera *and* from across the floor in Gemba Walk.
2. Model the core loop on Idle Miner Tycoon's 3-stage choke-point structure, but make the Theory-of-Constraints framing explicit and named in the UI ("Line 1: Press Station is the bottleneck") — teach the real vocabulary while playing, don't just imply it mathematically.
3. At any given moment exactly one purchase should read as "the obvious next step": surface and highlight the cheapest upgrade that would unblock the current red machine. Never present ten equally-plausible options with no guidance — this is the single most-repeated "wall" complaint in the genre.
4. Gate lean-tool unlocks (SMED, 5S, Kanban, TPM, Poka-Yoke, Heijunka, Andon) behind actually hitting the bottleneck each one solves, not a generic tech tree — e.g., SMED unlocks the moment changeover time becomes the visible constraint.

### Pillar 2 — watching the line flow is the reward
5. Conveyor speed and item spacing must visibly change the instant an upgrade lands. Treat "no upgrade should be visually invisible" as a hard QA checklist item — this is what shapez 2 and Satisfactory both get right and any idle game with a visible line cannot afford to get wrong.
6. Give every machine a layered audio state (idle hum → working chug → strained/blocked rattle), and let the overall factory soundscape thicken as more machines come online — directly reusing Satisfactory's "hum of equipment powering up" and its Production Amplifier's distinct-drone-when-active pattern.
7. Keep the floor small, linear and readable — a fixed, upgradeable line beats a free-build sandbox, both for a small team's scope and for the "walk the bus" legibility shapez 2 proves matters.
8. Make Gemba Walk mode earn its keep with proximity-based spatial audio and emissive machine-state lighting (red/amber/green) readable from a distance — this is the one place we can beat every 2D/top-down competitor, since none of the comps above combine idle pacing with true first-person floor-walking.

### Pillar 3 — real lean tools, one-line plain-English tooltips
9. Every tooltip must stand alone with zero external reference needed. Melvor Idle's most-repeated complaint — "borderline unplayable without a wiki tab open" — is the failure mode to design against; any tooltip that would need a wiki to clarify is a bug.
10. Introduce exactly one new mechanic or tool every 3–5 minutes for the first hour, each with an immediate, visible payoff — matches the general idle-onboarding finding that engagement decays fast and the "first dopamine loop" has to land before a player tabs away for good.
11. Pair the plain-English line with the real term every time ("Quick Changeover (SMED): swap tooling in seconds, not minutes") and always show the effect as a concrete before/after number, not flavor text alone.

### Pillar 4 — numbers go up forever, prestige, generous offline
12. Target **first prestige at 30–45 minutes of active play** — long enough to learn the core loop and feel the first real cost wall, short enough to deliver the reset payoff before a first-time player would drop off. (Synthesizes the 0–30-minute "hook phase" research with the wide real-world range of ~20 seconds to ~120 minutes; 30–45 minutes is the reasonable center for a premium, non-ad-funded title where sessions run longer than mobile.)
13. Re-skin prestige entirely in fiction so it never reads as "starting over": frame it as selling this factory and buying a bigger one, and **permanently keep unlocked lean-tool knowledge and tooltip glossary across resets** even as the numeric economy resets — this directly answers "prestige feels like starting over," the most damaging complaint category for the pillar.
14. Use a "bumpy" cost/production curve — alternating faster and slower stretches — rather than one smooth exponential; pure smoothness reads as grindy, and occasional fast stretches make each reset feel earned.
15. Offline earnings must appear as an **animated count-up on return**, never a silent lump sum applied in the background — this single UI moment is what turns "offline progress exists" into "offline progress feels rewarding."
16. Because there are no IAPs to protect, offline earnings can be genuinely generous — full-rate for the first ~8–12 hours, tapering after — framed in-fiction as "the night shift kept running." Good UX and good theme, for free.

### Pillar 5 — no microtransactions or dark patterns
17. Explicitly reject the "pay-or-wait" pattern that funds 60% of Idle Miner Tycoon's revenue via ads: the $4.99 upfront price is the entire monetization plan — no energy timers, no ad-gated speedups, no premium currency, ever.
18. Automation that mobile idle games sell as an IAP (auto-buyers, "managers") should instead be *earned* through lean-tool progression — Kanban unlocks auto-reordering, Andon unlocks auto-alerts — so automation keeps reading as a reward, never as a purchase.

---

## Do NOT copy (complexity traps)

1. **Freeform belt-routing as a puzzle** (splitters, mergers, undergrounds, priority routing) — this puzzle *is* the entire Satisfactory/Factorio/shapez 2 genre; our line should be fixed-topology and upgraded in place, never hand-laid.
2. **Deep multi-tier recipe/item trees** and "thousands of items" scale — Satisfactory's late-game item count is a scope trap that also fights the "always one obvious next step" pillar directly.
3. **Physics-simulated parts on conveyors** — MineMogul's "conveyors overflow, parts scatter" is charming in trailers but is the cited cause of its own performance problems and stuck-item bugs; use simple state-driven/scripted item movement instead, especially since the itch.io demo has to run over WebGL in a browser.
4. **Large open-ended or destructible 3D worlds** — Astro Colony's fully destructible voxel planets look impressive but reviewers say the underlying automation "doesn't grasp what makes it satisfying," and the ambition caused bugs and performance issues. Keep the floor small and mostly fixed.
5. **Free-build base construction across a big map** — a strength for MineMogul and Satisfactory, but a scope and clarity risk for a small team chasing "always one obvious next step."
6. **Multiplayer/co-op** — explicitly out of scope. Even MineMogul, a much bigger-scoped title, gets criticized for lacking it, which shows it's an expectation at *that* scope, not at idle-game scope.
7. **Live-ops content cadence, seasonal passes, ad monetization** — this is what makes Kolibri's mobile model work, but it directly conflicts with pillar 5 and with a premium one-time-purchase Steam release.

---

## Pricing & funnel notes for a $4.99 launch

- $4.99 is not a discount-tier guess — it's where **Cookie Clicker itself** sells on Steam, alongside **Shelldiver** at the same price and **Increlution** just below at $3.99. This is a proven, well-populated price for a well-received idle/incremental premium title.
- Position the store page explicitly as **idle/incremental with a 3D factory you can walk**, not as "factory automation builder" — MineMogul's own player feedback shows its fans want deeper freeform building than an idle-paced game is designed to deliver; a mismatched pitch would draw the wrong reviewers and hurt review score, not just conversion.
- The itch.io free web demo **is** the funnel — mirror or port it as a free Steam demo timed to a Next Fest. Idle/incremental is reportedly the single most-entered tag at Next Fest, so the trailer and store capsule need to lead with the visual hook (a machine glowing red → the fix → flow resuming) in the first seconds, not with genre boilerplate.
- Benchmark wishlist-to-buyer conversion at **10–20%** generally (12–17% typical during Next Fest itself, 26–32% excellent, under 5% is a real problem to diagnose).
- **Keep the demo live after Next Fest ends** rather than pulling it — this alone correlates with 20–30% more wishlists gained in the pre-launch window.
- Target genuine Steam Deck **Verified** status (full controller support for both the orbit camera and Gemba Walk, native Deck resolution) — most idle competitors default to trackpad-only, so full controller support is comparatively cheap, achievable differentiation that also surfaces us in Deck-specific curated sales.

---

## Sources

- [MineMogul on Steam](https://store.steampowered.com/app/3846120/MineMogul/)
- [MineMogul player feedback thread](https://steamcommunity.com/app/3846120/discussions/0/695376132937130829/)
- [MineMogul 7hr review thread](https://steamcommunity.com/app/3846120/discussions/0/667222425710142351/)
- [Gamerant: MineMogul like Minecraft meets Satisfactory](https://gamerant.com/steam-games-like-minecraft-satisfactory-minemogul/)
- [Idle Miner Tycoon Fundamental Gameplay wiki](https://idleminertycoon.fandom.com/wiki/Fundamental_Gameplay)
- [GameAnalytics: 8 Lessons from Kolibri Games](https://www.gameanalytics.com/blog/making-a-hit-idle-game-eight-lessons-from-kolibri-games)
- [Mr. Mine and the Reinvention of the Idle Genre](https://blog.mrmine.com/mining-game-spotlight-mr-mine-and-the-reinvention-of-the-idle-genre/)
- [GamesRadar: optimizing conveyor belts in Satisfactory](https://www.gamesradar.com/games/strategy/forget-aaa-this-year-all-i-wanted-to-do-was-optimize-my-conveyor-belts-in-satisfactory/)
- [Game8: Satisfactory Review](https://game8.co/articles/reviews/satisfactory-review)
- [PC Gamer: Satisfactory review](https://www.pcgamer.com/games/sim/satisfactory-review/)
- [Medium: Satisfactory — The Factory Must Grow, Always](https://medium.com/@erwan.prastiawan97/satisfactory-the-factory-must-grow-always-e26271887fe2)
- [Satisfactory Wiki: Production Amplifier](https://satisfactory.wiki.gg/wiki/Production_amplifier)
- [Cookie Clicker Wiki: Progression Stages](https://cookieclicker.wiki.gg/wiki/Progression_Stages)
- [Medium: Cookie Clicker Analysis](https://kalebnek.medium.com/cookie-clicker-analysis-bf3787aa96d7)
- [Dinogame: How Cookie Clicker's Progression Curve Works](https://dinogame.gg/blog/how-cookie-clicker-progression-works/)
- [GameDeveloper: The Math of Idle Games, Part III](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii)
- [Eric Guan: Idle Game Design Principles](https://ericguan.substack.com/p/idle-game-design-principles)
- [SteamDB: Melvor Idle](https://steamdb.info/app/1267910/)
- [Steam Revenue Calculator: Melvor Idle](https://steam-revenue-calculator.com/app/1267910/melvor-idle)
- [The Perfect Tower II on Steam](https://store.steampowered.com/app/1197260/The_Perfect_Tower_II/)
- [Increlution on Steam](https://store.steampowered.com/app/1593350/Increlution/)
- [Increlution reviews — Steambase](https://steambase.io/games/increlution/reviews)
- [Idle Slayer on Steam](https://store.steampowered.com/app/1353300/Idle_Slayer/)
- [Alinea Analytics: Wishlist-to-buyer conversions with Next Fest demos](https://alineaanalytics.substack.com/p/wishlist-to-buyer-conversions-for)
- [StraySpark: Steam Next Fest Demo Optimization](https://www.strayspark.studio/blog/steam-next-fest-demo-optimization-wishlists)
- [Gamosy: Steam Next Fest Survival Guide](https://gamosy.com/blog/steam-next-fest-guide)
- [GG.deals: Steam Deck Verified games list](https://gg.deals/games/steam-deck-verified/)
- [Steam Deck HQ: Steam Idler Fest idle games](https://steamdeckhq.com/news/steam-deck-idle-games-2025-steam-idler-fest/)
- [Metacritic: Astro Colony](https://www.metacritic.com/game/astro-colony/)
- [Game8: Astro Colony Review](https://game8.co/reviews/astro-colony/astro-colony-review)
- [Yardbarker: Astro Colony Review](https://www.yardbarker.com/video_games/articles/astro_colony_review_a_space_factory_sim_that_dreams_big_but_trips_over_its_own_gravity_boots/s1_17456_44081651)
- [NGOHQ: Shapez 2 Review](https://www.ngohq.com/2026/04/23/shapez-2-review/)
- [shapez 2 on Steam](https://store.steampowered.com/app/2162800/shapez_2__Factory/)
- [Whisper of the House: Shapez 2 Logistics Guide](https://www.whisperofthehouse.com/shapez-2/space-belts-trains-guide)
- [RetroStyleGames: Low Poly Game Art Guide](https://retrostylegames.com/blog/low-poly-game-art-an-ultimate-guide/)
- [NextBigGames: Idle Games on Steam Revenue Trends 2026](https://nextbiggames.com/2026/05/09/idle-games-on-steam-revenue-trends-2026/)
- [GrowthMarketReports: Idle Games Market Research Report](https://growthmarketreports.com/report/idle-games-market)
- [Factorio-BottleneckLite mod (GitHub)](https://github.com/raiguard/Factorio-BottleneckLite)
- [Factorio Bottleneck mod](https://mods.factorio.com/mod/Bottleneck)
- [GG.deals: 50 must-have indie games under $5](https://gg.deals/wallet-friendly/the-50-must-have-indie-games-under-5-for-your-steam-collection/)
- [Melvor Idle negative reviews (wiki-dependency complaint)](https://steamcommunity.com/app/1267910/negativereviews/)
