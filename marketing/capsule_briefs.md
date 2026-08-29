# Capsule Art Direction Brief

For an artist or an image model. Covers every Steam capsule size plus the itch.io cover. All
sizes should be built from the **same hero scene** (recomposed/recropped per format, not
independently art-directed) so the storefront presence reads as one consistent picture: a dark
factory floor with exactly one machine glowing wrong.

---

## Shared direction (applies to every size)

**Scene:** A 3/4-elevated factory-floor angle — halfway between the game's orbit camera and its
first-person Gemba Walk, so it reads as "a real 3D place," not a flat icon. Two or three machines
in frame along a short conveyor run. One machine glows alarm red-orange. The other(s) glow
healthy green. That contrast **is** the entire pitch — every crop at every size should preserve it
before anything else.

**Palette** (pulled directly from the game's own UI palette — `docs/ARCHITECTURE.md` §14 — so
capsule art and in-game screenshots feel like the same object):

| Role | Hex | Use |
|---|---|---|
| Background / deep shadow | `#17191D` | Ambient dark, falloff, vignette |
| Floor | `#23262B` | Factory floor material |
| Panel dark | `#1E2126` | Secondary surfaces, machine bodies |
| Text / off-white | `#E8EAED` | Wordmark fill, light accents |
| Amber (brand accent) | `#F4B942` | Sparks, practical lights, conveyor edge glow — sparing accent, never the focal color |
| Green (healthy) | `#3FA34D` | Running-station status glow |
| Red-orange (bottleneck) | `#E4572E` | The one wrong machine. The whole point. |
| Grey (starved) | `#9AA0A6` | Unlit/idle machine bodies, not a hero color |

**Style:** Clean low-poly geometry built from simple primitives, near-black background, emissive
glow doing the work texture normally would ("lighting is your best texture" — see
`docs/RESEARCH.md` §5). No clutter, no busy background detail — every render needs generous
negative space around the hero machine so it survives being scaled down to 231×87 without turning
to mush.

**What NOT to do:** no freeform sprawling factory vista (this is a small, linear line, not an
open-world base — don't imply a scope the game doesn't have), no photoreal textures, no more than
one red machine in frame (a field of red reads as "everything is broken," not "here is the one
thing to fix" — the whole design pillar is *exactly one* obvious problem at a time).

---

## Title treatment

- **Wordmark:** "BOTTLENECK" (working title — confirm final title before art lock; see
  `INTEGRATION_NOTES.md`).
- **Typeface direction:** bold, condensed, industrial sans — think Oswald / Bebas Neue / Archivo
  Black territory. All-caps, squared terminals, stenciled-factory-signage feel. No rounded,
  friendly, or script forms — this is a machine placard, not a mobile-game mascot logo.
- **Color:** off-white (`#E8EAED`) body. Reserve the red-orange (`#E4572E`) for exactly one small
  accent element, not the wordmark itself — red stays meaningful (it means "look here" in the
  actual game) instead of becoming decorative.
- **Beacon dot:** a small glowing red-orange circle used as a full-stop / accent near the
  wordmark — direct continuity with the existing app icon (`icon.svg`), which already uses a
  red-orange beacon dot as its central device. Same glyph, every asset, every size.
- **Chevron / conveyor motif:** a single sparse row of thin chevron ticks (› › ›) under or beside
  the wordmark baseline — reads as both a conveyor's direction-of-flow arrows and a
  hazard-stripe pattern. Use once, thinly. Never tile it into a busy background texture.

---

## Per-size specs

### Header Capsule — 460×215
**Where it appears:** search results, category/tag browsing, top of the store page — the single
highest-traffic image across the whole Steam presence. Treat this as the master render.
**Composition:** tight 3/4 crop on 2–3 machines; the red machine dead-center or on the near-side
rule-of-thirds line, green machine(s) flanking. A short conveyor segment only — not the full
six-station line, which turns to noise at this size.
**Text-safe area:** wordmark + chevron lockup in the lower-left third. Leave the right ~15% of
the frame comparatively calm — some browse layouts place tags/badges near that edge.
**Bar to clear:** must read as "one red machine among green ones" in under a second at native
size in a crowded search grid.

### Small Capsule — 231×87
**Where it appears:** wishlist rows, "you may also like" rails, recently-viewed — small, squeezed
between text.
**Composition:** crop tighter than the header — essentially just the red machine and a sliver of
one green neighbor filling the frame edge-to-edge.
**Text-safe area:** none — no baked wordmark at this size; type is illegible below roughly 20px
cap-height, so this size sells purely on the red/green silhouette.
**Bar to clear:** the hardest size in the set. Run an actual squint/blur test on the export: if
the red glow isn't still the single brightest thing in frame when blurred, recrop tighter.

### Main Capsule — 616×353
**Where it appears:** featured/curated storefront placements — the most breathing room of any
capsule size.
**Composition:** same hero as the header capsule, pulled back slightly to reveal 3–4 stations and
visible WIP boxes queued on the conveyor (the "there's a whole system here" beat that the tiny
capsules can't afford).
**Text-safe area:** full wordmark + chevron lockup, lower-left quadrant. Keep the top-right
quadrant comparatively clear — some placements overlay a "New" or discount ribbon there.

### Vertical Capsule — 374×448
**Where it appears:** portrait-oriented browsing modules (mobile Steam app, some grid views).
**Composition:** a genuine portrait reframe, not a crop of the horizontal hero — raise the camera
slightly and look down the line so the tall frame fills with conveyor-in-depth (stations stacked
front-to-back) rather than empty floor or sky. Red machine sits in the upper-middle third; some
portrait grids crop the bottom edge first, so keep it clear of anything essential.
**Text-safe area:** wordmark in the bottom third, on a darkened floor gradient for contrast.

### Page Background / Hero — 1232×706 (+ ultra-wide "Library Hero" variant, 3840×1240)
**Where it appears:** sits *behind* the store page's own content at 1232×706 — this is backdrop,
not foreground, so it must stay calmer and lower-contrast than every other asset or it'll fight
the page text sitting on top of it. Use a pulled-back, slightly desaturated version of the hero
scene, not the punchy header-capsule crop.
**3840×1240 note:** same scene, recomposed for a much wider/shorter aspect ratio (this is the
Library-page-style ultra-wide background) — extend the conveyor run left and right rather than
just upscaling the 1232×706 art, and keep the red machine centered, since the two edges get
cropped differently across different client window sizes.
**Text-safe area:** darken the top ~20% and bottom ~15% via gradient so store UI and buttons
overlaid on top stay legible in both the light and dark Steam client themes; keep the busiest
detail (and the red glow) in the vertical center band.

### Library Capsule — 600×900 (portrait)
**Where it appears:** the Steam client Library, once a player owns or has wishlisted the game —
seen far more often than the store page itself for a returning player.
**Composition:** the same reframe as the 374×448 vertical capsule, rebuilt at native resolution
(don't just upscale the smaller export — re-render).

### Library Header — 920×430
**Where it appears:** Library list view.
**Composition:** same framing as the Main Capsule, but the Library UI overlays play-button chrome
along the bottom edge — keep the bottom ~20% low-detail and dark so those controls stay legible.
**Text-safe area:** title lockup in the upper half instead of the lower-left (opposite of the
store capsules, because the bottom is reserved for Steam's own controls here).

### Logo — transparent wordmark
**Where it appears:** composited by Steam *over* the Library Hero and some store modules — over
whatever background Steam's own layout puts behind it, not necessarily our art.
**Spec:** "BOTTLENECK" wordmark only — no machine art baked in. Transparent PNG, off-white
(`#E8EAED`) fill, thin dark (`#17191D`) contrast edge/drop shadow so it stays legible over
unpredictable backgrounds, chevron tick motif under the baseline, single red-orange beacon-dot
accent per the Title Treatment above. Author on a generous canvas (recommend 1280×720) with the
wordmark occupying roughly the center 60%, so it survives aggressive automatic cropping.

---

## itch.io cover image

itch.io's cover (roughly landscape, displayed small in browse grids) should reuse the **Header
Capsule** composition and crop rather than get separately art-directed — same hero render, same
text-safe logic. Keeps the itch page and the Steam funnel visually continuous for anyone who
clicks through from one to the other.

---

## Readability checklist (run before any asset is called final)

1. **Grayscale test** — desaturate the export. The composition should still read as "something is
   different about that one machine" from shape and glow intensity alone, not hue alone — this
   matches the in-game status telegraphing itself, which is deliberately colorblind-safe (icon +
   color together, `docs/ARCHITECTURE.md` §8).
2. **Thumbnail test** — view the Small Capsule (231×87) at actual pixel size, not zoomed in.
3. **Squint test** — blur every export slightly; confirm the red glow is still the single
   brightest, most legible element in frame at every size.
4. **One red machine, always** — never more than one glowing red in any single composition. More
   than one reads as "everything here is broken," which is the opposite of the pitch.
