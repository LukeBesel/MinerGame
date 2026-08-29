# Launch Checklist

Relative timeline (T-minus counts down to Launch Day, T-0). Anchor these to a real calendar date
once one is picked — until then, treat every T-marker as "weeks before/after launch," not a fixed
date. One illustrative pass is included per phase so this reads as a usable plan, not a template.

**Sequencing principle:** the itch.io demo has zero platform dependencies, so it goes up first.
The Steam store page has to exist in "Coming Soon" state shortly after, because the demo's own
call-to-action ("wishlist on Steam") is meaningless until it does. Everything else — posts,
devlogs, Next Fest — flows from there.

---

## Timeline

| When | Action |
|---|---|
| **T-14 weeks** | itch.io demo goes live (`demo_scope.md` build). Steam store page goes live in "Coming Soon" state within the same week, using `store_page.md` copy and whatever capsule art from `capsule_briefs.md` is ready — even placeholder-quality art beats no page, since wishlisting can't start until the page exists. |
| **T-13 weeks** | First community posts: r/incremental_games soft-intro post (draft below) and manufacturing/ops subreddit post (draft below). Framed as "here's a free demo, genuinely want feedback" — not a launch announcement, because it isn't one yet. |
| **T-12 to T-3 weeks** | Weekly devlog beats (cadence below) — one per week, cross-posted to the Steam page's own announcements (where wishlisters actually see it), itch devlog, and wherever else has an audience (a subreddit's weekly self-promo thread if one exists, is generally the *right* venue for repeat posts — better than repeated top-level posts). |
| **T-10 weeks (or as soon as applications open for the nearest window)** | Apply for Steam Next Fest. Next Fest runs roughly three times a year (historically February / June / October) — confirm the actual next open window on Steamworks and shift every T-marker in this table to match; don't hardcode a real date here without checking. |
| **Next Fest week** | Steam demo build live (not just itch — Next Fest traffic lands on the Steam page), trailer live, capsule art final, daily active presence in the Steam discussion/comments during the event. Track wishlist conversion against the benchmarks in `docs/RESEARCH.md` §4: 12–17% is typical *during* Next Fest itself, below 5% means something's actually wrong, 26–32% is excellent. |
| **T-1 week** | Final asset lock (trailer, all capsule sizes, store copy). Press/streamer outreach to idle-game-friendly YouTubers and streamers (keys + a short, honest pitch — see tone note below). Launch-day subreddit posts drafted in advance; re-check each target subreddit's self-promo rules, since they can change. |
| **Launch Day (T-0)** | Store page flips from "Coming Soon" to purchasable. Price live at $4.99 with the modest launch-week discount (policy below). Trailer goes live everywhere at once. r/incremental_games launch-day post (second post — the "it's out" follow-up to the earlier feedback post, thanking anyone who played the demo). Manufacturing/ops subreddit follow-up, same tone. Founder actively present in Steam reviews/discussions and Reddit comments for the first 48–72 hours — this window has the highest leverage of the entire launch. Keep both demos (itch + Steam) live post-launch; they don't stop earning wishlists just because launch happened. |
| **T+1 week** | Patch anything launch week surfaced. One recap devlog/post thanking the community, no further price moves. |
| **T+1 month** | Steady review-response cadence. Decide the first small post-launch patch based on actual player feedback. Hold price at $4.99 — no early discounting; a fast discount right after launch reads as "this wasn't worth full price" to the people who just paid it. |
| **T+3 months** | First post-launch content beat ships (candidates below). Modest participation in Steam seasonal sales going forward (10–20% typical range) — save deeper cuts (33%+) for major sale events well after launch, not the first few months. |
| **T+6 months (or once a content beat judged substantial has shipped)** | Price rises to $6.99, reflecting real added content. Existing owners keep whatever they paid — that's a Steam platform guarantee, not a policy choice, but worth restating in the announcement anyway since players ask. |
| **T+9–12 months** | Second product line ships (see roadmap below) — its own devlog arc and a second marketing push, same tone as launch. |

---

## r/incremental_games — soft-intro post (T-13 weeks)

**Title:**

> I built an idle factory game where "find the bottleneck" is the entire strategy layer — free demo, feedback very welcome

**Body (151 words):**

> Hi all — I'm building Bottleneck, an idle/incremental factory game built around Theory of
> Constraints: your line only moves as fast as its worst station, and that station glows red so
> you always know what to fix next.
>
> You grow from three humble machines into a six-station line, spending Kaizen Points on real
> lean tools (SMED, Kanban, TPM, and more) as you actually hit the problems they solve, not a
> generic tech tree. Prestige ("Kaizen Event") keeps your whole skill tree, so it never feels
> like starting over. Offline progress is generous — there's nothing else to sell you instead.
> One price, no ads, no IAP, ever.
>
> There's also a first-person mode where you walk your own factory floor, which I haven't seen
> elsewhere in the genre.
>
> Free demo's up on itch.io: [link]. Genuinely want feedback from people who know this genre
> cold — pacing, prestige curve, anything that feels off.

**Tone notes:** no astroturf, no "check out my game!!" energy, no fake reviews or planted
comments. It's a dev, it says it's a dev, it asks a real question at the end and means it. Answer
every comment for at least the first 24 hours — r/incremental_games is a genuinely knowledgeable
crowd on pacing and prestige math specifically, and their feedback is worth having, not just worth
surviving.

---

## Manufacturing/ops subreddit post (T-13 weeks)

**Target subreddits:** r/manufacturing, r/IndustrialEngineering, r/sixsigma / r/LeanSixSigma —
**verify each subreddit's current name and self-promotion rules before posting.** Several
engineering/manufacturing subs disallow product or game posts outright, or require mod
pre-approval; getting a post silently removed costs less goodwill than not checking first. Where
a sub is stricter, consider a comment in an existing relevant thread (a "games about your job"
or lean-manufacturing-humor thread) instead of a cold top-level post.

**Title:**

> A factory game where "go do a Gemba walk" is an actual first-person camera mode

**Body (~135 words):**

> Small team, building an idle/incremental game called Bottleneck around Theory of Constraints —
> the bottleneck machine on the line literally glows red, and you clear it with real tools:
> SMED, 5S, Kanban, TPM, Poka-Yoke, Heijunka, Andon, each explained in plain English the moment
> it's actually relevant, not up front as a wall of jargon. There's also a Gemba Walk mode —
> genuine first-person, you walk your own line and watch OEE and station status from the floor.
>
> It's a game, so obviously simplified, but we tried hard not to be wrong about the underlying
> ideas. Free browser demo on itch.io if any of that sounds like your kind of nonsense: [link].
> Genuinely curious whether it holds up for people who do this for a living — go easy, but not
> that easy.

---

## Weekly devlog cadence (T-12 to T-3 weeks, ~10 beats)

| Week | Beat | Hook |
|---|---|---|
| 1 | Why lean manufacturing | The pitch: Theory of Constraints as a game loop. Screenshot: hour-0, one red machine. |
| 2 | The bottleneck beacon | How the always-on red/amber/green/grey status system works, colorblind-safe by design. GIF. |
| 3 | Teaching real tools without a wiki | SMED/Kanban tooltip philosophy — plain English, real term, concrete before/after number. |
| 4 | Prestige that doesn't reset your brain | The Kaizen Event: sell the factory, buy a bigger one, keep the whole skill tree. |
| 5 | Gemba Walk, first look | First footage of the first-person mode. Video, not just screenshots. |
| 6 | The night shift kept running | Offline progress devlog — why it's generous, and why there's nothing to sell instead of it. |
| 7 | Numbers, but bumpy | Why the cost curve isn't one smooth exponential, and why that matters for how a reset feels. |
| 8 | Building a factory out of primitives | Low-poly + emissive art direction — "lighting is your best texture." Before/after render. |
| 9 | Steam Deck, for real | Controller support for both the orbit camera and Gemba Walk — most idle games skip this. |
| 10 | Next Fest is coming | Countdown post. Demo polish pass. Direct ask: wishlist + follow for the event. |

---

## Price & discount policy

- **Launch price: $4.99**, with a modest launch-week discount (10% — roughly $4.49) using
  Steam's own new-release visibility discount window. This is the proven price point for the
  genre: it's exactly where Cookie Clicker itself sells on Steam, alongside Shelldiver at the
  same price (`docs/RESEARCH.md` §4).
- **Hold at $4.99** through the first several months post-launch — no early markdown. A fast
  discount right after launch undercuts the people who paid full price in week one.
- **Rise to $6.99** once a substantial post-launch content beat has shipped (target: ~T+6 months,
  tied to content, not the calendar) — reflecting real added scope, not a arbitrary price hike.
  Existing owners never pay the difference; that's how Steam pricing works regardless of policy.
- **Ongoing sales:** participate in seasonal Steam sales at a modest 10–20% discount; reserve
  deeper cuts (33%+) for major sale events well after launch, once the game has had time to
  establish a full-price identity.

---

## Post-launch content beats

Both beats below are already the team's own stated post-launch roadmap
(`docs/BUILD_PLAN.md`, "Post-plan"), not new scope invented here — this section just sequences
them for marketing purposes.

1. **Supplier system** (earlier, smaller beat, ~T+3 months): the first station currently has
   infinite raw material for simplicity — a supplier system would turn that into a real
   subsystem (negotiate incoming material cost/quality), giving the front of the line the same
   kind of depth the back end already has. Devlog-friendly on its own.
2. **Customer/demand system** (could ship alongside or after suppliers): the last station
   currently sells output instantly at a flat price — contracts, demand fluctuation, or
   negotiated pricing would give the back of the line more to manage, mirroring the supplier
   beat from the other direction.
3. **Second product line** (larger beat, ~T+9–12 months): a second product family running
   through the plant — new stations and/or new skill-tree depth, positioned as its own
   mini-launch with its own trailer and devlog arc, aimed at both new wishlists and re-engaging
   players who finished the original line.

Exact order between beats 1 and 2 is a design call, not a marketing one — sequence whichever is
actually ready first; both make an equally good devlog.
