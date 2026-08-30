# Store Page Copy

Steam splits "About This Game" into rich text, but the task brief wants short description, long
description (feature bullets), and the About narrative broken out separately — they're kept
separate below so each can be pasted into its own Steamworks field. In practice, Steamworks'
actual "About This Game" field is a single rich-text box: paste **Long description** followed by
**About This Game** into it as one continuous flow, in that order. Steam formatting uses its own
BBCode-style tags (`[b]`, `[list][*][/list]`, `[h2]`) — convert the `**bold**` and `-` bullets
below when pasting; don't paste raw Markdown into Steamworks.

---

## Short description (Steam field, 300-char limit)

**Primary (250 chars):**

> One machine is glowing red and it's lying about being the only problem. An idle factory game
> built on real lean manufacturing: find the bottleneck, fix it, prestige into a bigger plant, and
> walk your own line in first person. No ads. One price. Ever.

**Alt, for A/B testing against the primary (249 chars — leads with idle-fan mechanics instead of
the visual hook; see `INTEGRATION_NOTES.md` for why the header capsule image, not this field, is
the higher-leverage A/B test):**

> Your factory has exactly one problem right now, and it's glowing red. Find the bottleneck, fix
> it with real lean tools (SMED, Kanban, TPM), watch the line flow, then prestige into a bigger
> plant. Idle-clicker pacing, zero ads, one purchase, forever.

---

## Long description (feature bullets — idle-fan hooks first, lean-tool flavor second)

Somewhere on this factory floor is exactly one machine that's actually stopping you from making
more money. Everything else is a distraction. Find it. Fix it. Watch the whole line breathe out
— then do it again, bigger.

**The loop:**

- **Numbers go up, forever.** Buy upgrades x1, x10, x100, or MAX. The cost curve is deliberately
  bumpy — some stretches fly, some make you sweat — so every purchase still feels like a decision,
  not a formality.
- **Real offline progress.** Close the game and the night shift keeps running. Come back to a
  count-up of everything you missed, not a silent number that just changed while you weren't
  looking.
- **Prestige that isn't "starting over."** Run a **Kaizen Event** and you sell this factory and
  buy a bigger one — production resets, but your entire skill tree, every lean tool you've
  unlocked, and all your Kaizen Points carry over. You keep getting smarter even when the money
  goes back to zero.
- **Always exactly one obvious next step.** The line's single worst constraint glows red — from
  the management view and from the factory floor — so you always know what to fix next. No wall
  of ten equally-plausible upgrades, no wiki tab required.

**Real lean tools, not flavor text:**

- Unlock **SMED, 5S, Kanban, TPM, Poka-Yoke, Heijunka,** and **Andon** as you actually hit the
  problems they solve — changeovers eating your uptime unlocks Quick Changeover, not a generic
  tech-tree gate. Every one ships with a plain-English one-liner, the real term, and a concrete
  before/after number. No jargon left unexplained.
- Spend Kaizen Points across a five-branch skill tree — **Flow, Reliability, Quality, Speed,
  People** — that persists through every prestige, forever.

**Walk your own factory:**

- Play the whole game from a mouse-only orbit camera, or hit Tab and drop into **Gemba Walk** —
  a genuine first-person mode where you walk the length of your own production line and watch
  every station's status light from the floor. As far as our research turned up, no other idle
  game lets you do this. We checked.

**No catch:**

- One purchase, no ads, no energy timers, no premium currency, no "watch a video to speed this
  up" — ever. The $4.99 (rising to $6.99 as the game grows post-launch) is the entire business
  model.
- Steam Deck support planned, with real controller input for both the orbit camera and Gemba
  Walk — most idle games on Deck default to trackpad-only; this one won't.

---

## About This Game (narrative section)

You've just inherited a struggling factory. It has one hand-cranked stamping press, a business
plan best described as "hope," and a bottleneck you can see from across the room, because it's
the machine glowing red.

**Bottleneck** is an idle/incremental game built on the Theory of Constraints: the idea that a
production line only ever moves as fast as its single worst station, and every dollar spent
anywhere else is a dollar wasted. Find the constraint. Fix it. Watch the next one appear
somewhere new. Six stations, one long conveyor, and a genuinely satisfying number that keeps
climbing.

Along the way you'll pick up the actual toolkit lean manufacturing uses to solve this for real —
SMED, 5S, Kanban, TPM, Poka-Yoke, Heijunka, Andon — each one taught the moment you need it, in
plain English, with the real term attached so it sticks. Every upgrade you buy is visible on the
line: faster conveyors, shorter queues, a beacon flipping from red to green in slow motion while
a chime plays, because that moment is the entire point of the genre and we are not going to
skimp on it.

Then you'll sell the place, buy a bigger one (we call it a **Kaizen Event**; you'll call it
prestige), and keep everything you actually learned. Come back tomorrow and the night shift
already ran without you.

Play the whole thing from a management-style orbit camera, or step down onto the floor in
first-person **Gemba Walk** mode — lean's actual term for "go see the real place of work" — and
watch your own factory hum, station by station, from ground level.

One price. No ads. No premium currency. Your consultant said this would take a six-week
workshop and a binder. It takes a mouse wheel.

---

## itch.io

**Tagline (one line):**

> Find the bottleneck. Fix it. Watch the line flow.

**Demo blurb (2 sentences, points wishlists at Steam):**

> This free browser demo is the first ~45 minutes of Bottleneck — enough to find your first
> bottleneck, unlock a few real lean tools, and run your first Kaizen Event. If you want to keep
> improving past that point, wishlist the full game on Steam — this demo stays up for good, but
> that's where the rest of the factory is.
