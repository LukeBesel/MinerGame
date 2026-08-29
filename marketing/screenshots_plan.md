# Screenshot Plan — 5 Staged Scenarios

Five scenarios, staged in the live build, covering the arc of a first playthrough: humble start →
first real complexity → the prestige moment → a mature line → the payoff view nobody else in the
genre has. Steam's screenshot carousel supports per-image captions — copy for each is included
below and should be attached as the image's caption/alt text in Steamworks.

**On numbers:** every stat below (money, pps, OEE, which station is the bottleneck, node counts)
is illustrative staging guidance, not a spec — final balance belongs to the sim/data modules.
Whoever captures these should hit the same *beats* (three stations vs. six, WIP piles present vs.
not, which panel is open) using whatever numbers the live build actually produces at that point
in a normal playthrough, not force specific digits.

**Format:** capture at a wide desktop resolution (1920×1080 minimum) with UI scale at default;
Steam displays screenshots up to full width, so avoid tiny illegible HUD text — legibility at the
carousel's actual display size matters more than matching a "cinematic" crop.

---

## Screenshot 1 — Hour 0: the honest problem

**Story beat:** the game's entire pitch in one frame, captured in the first few minutes of a
fresh save.

- **Camera:** default orbit camera, its starting position — 3/4 elevated angle framing all three
  starting stations (Stamping Press, CNC Lathe, Weld Cell) left-to-right, with the locked slots
  for Paint Booth / Assembly Cell / QA & Packout visible beyond them as dim, unlit silhouettes
  (teases the six-station line without spending any screenshot slots on "coming later" callouts).
- **On screen:** a short conveyor connecting the three running stations. One of the three is
  flagged with the pulsing red-orange bottleneck beacon and its "!" marker; the other two show
  healthy green status LEDs. A thin trickle of parts is moving — this is clearly early, clearly
  slow, and clearly readable.
- **HUD state:** top bar showing a small starting money figure, parts/sec well under 1, a modest
  OEE percentage, and the bottleneck readout naming the flagged station explicitly (e.g.
  "Bottleneck: Weld Cell"). Buy multiplier at x1. Left panel showing that station's card with its
  four upgrade buttons visible, at least one clearly affordable/highlighted as "helps the
  bottleneck." No side panels (skill tree/Kaizen) open yet.
- **Caption:** *"Day one. Three machines, a business plan best described as 'hope,' and a
  problem that's honest enough to glow red about it."*

---

## Screenshot 2 — Hour 1: the line has opinions now

**Story beat:** enough time has passed that the floor looks like a real production line under
real strain — the "walk the bus until you find the stalled building" readability the game is
built around (`docs/RESEARCH.md` §5), captured mid-struggle rather than mid-triumph.

- **Camera:** orbit camera pulled back and rotated slightly further down the line than shot 1, so
  a fourth station (Paint Booth, freshly unlocked) is in frame alongside the original three.
- **On screen:** a visibly grown WIP pile of parts queued in front of the current bottleneck
  station, a small amount of scrap visible in a scrap bin, and the conveyor now dense enough with
  moving parts to read as "busy" rather than "trickling." The Coach/Andon hint board is visible
  with a live, actionable hint bubble pointed at the current constraint.
- **HUD state:** money in the low hundreds-to-thousands range, parts/sec meaningfully higher than
  shot 1, OEE mid-range (there's clearly room to improve — that's the point), buy multiplier at
  x10. Left panel open on the bottleneck station's card.
- **Caption:** *"Forty-five minutes in and the line finally looks like a line. That pile of boxes
  isn't decoration — it's a receipt."*

---

## Screenshot 3 — First Kaizen Event: the prestige preview

**Story beat:** the moment a first-time player learns prestige isn't a punishment — the numbers
in this panel are the whole sales pitch for the mechanic.

- **Camera/framing:** the factory floor visible but dimmed/softly blurred behind the UI, standard
  modal treatment — the panel is the subject of this screenshot, not the floor.
- **On screen:** the right-panel **Kaizen Event** tab, open and populated: current Continuous
  Improvement Points, the CIP gain this event would grant, the global throughput multiplier shown
  as a clear before → after pair, lifetime parts produced versus the threshold required, and an
  enabled (not greyed-out) confirm button.
- **HUD state:** top bar still visible above the panel showing a healthy money figure and a
  six-figure-or-better lifetime parts count, signaling "this took real progress to reach," not a
  five-minute reset.
- **Caption:** *"The money resets. You don't. Kaizen Event #1: sell the factory, keep everything
  you actually learned, buy a bigger one."*

---

## Screenshot 4 — Mid-game: the full line, and the tree behind it

**Story beat:** shows both halves of the game's depth at once — a fully built six-station line
running clean, and the skill tree that's been feeding it.

- **Camera:** orbit camera pulled back further than any prior shot, framing the entire six-station
  line left-to-right in one continuous conveyor run — Stamping Press through QA & Packout, all
  unlocked, all running.
- **On screen:** every station showing a healthy green status LED (or at most one clearly-flagged
  bottleneck further down the line — the constraint has moved, it hasn't disappeared), small and
  well-managed WIP piles rather than overflowing ones, and the conveyor moving at a visibly
  brisker pace than shots 1–2. Overlaid, the right-panel **Skill Tree** tab is open, showing all
  five branch columns (Flow, Reliability, Quality, Speed, People) with prerequisite lines drawn
  and a substantial number of nodes already purchased/lit up.
- **HUD state:** money shown in suffixed BigNum notation (e.g. the low-to-mid thousands-and-up
  range), parts/sec clearly higher than shot 2, OEE in the 70s–80s%, buy multiplier at x100 or
  MAX.
- **Caption:** *"Six stations, mostly green, and a skill tree that still isn't finished. This is
  the part where a real consultant would start charging by the hour."*

---

## Screenshot 5 — Late game: Gemba Walk, from the floor

**Story beat:** the payoff shot, and the one no comparable idle game can produce — a fully
automated plant, seen on foot, from inside it.

- **Camera:** first-person **Gemba Walk** mode (Tab), standing partway down the line, looking
  along its length so multiple stations are visible in perspective, all glowing steady green,
  with visible ambient practical lighting (amber accents, sparks at the weld cell) rather than
  flat even lighting — this shot should look and feel different in kind from the orbit-camera
  shots, not just closer.
- **On screen:** a mature, fully automated line — every station green, conveyor moving briskly
  and continuously, no visible WIP backup anywhere, scrap bins near-empty. Nobody needs to be
  actively managing anything in this frame, and it should read that way.
- **HUD state:** deliberately minimal — a small persistent money/pps readout at most, no open
  panels — so the 3D scene itself is the entire subject of the screenshot. A large money figure
  and a multi-digit Kaizen Event count (visible in stats if included) signal how far "late game"
  this is, without needing a panel open to prove it.
- **Caption:** *"Nobody's touched this line in a while. You just came down to watch it work.
  That's allowed."*
