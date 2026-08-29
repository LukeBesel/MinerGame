# Steamworks Achievements — Paste List

## What this file is

This table is **auto-fillable from `src/data/achievements.json`**, which is being authored in
parallel by the data module and does not exist yet as of this writing (`src/data/` currently
holds only a stub loader). Per `docs/ARCHITECTURE.md` §7, that file will contain 25–35 entries,
each with an `id` matching `^ACH_[A-Z0-9_]+$` (the exact string Steamworks needs as the API Name),
a `name_key` and `desc_key` resolving through `src/data/locale/en.json`, and a `trigger` drawn
from the same vocabulary as milestones (`lifetime_parts`, `money_earned`, `pps`, `oee`,
`bottleneck_cleared_count`, `station_unlocked`, `upgrade_count`, `skill_count`, `prestige_count`,
`zero_scrap_seconds`).

**Once `achievements.json` ships, whoever integrates it should:** walk the array in file order
(Steamworks displays achievements in list order, and order reads as a natural unlock narrative —
preserve it rather than alphabetizing), resolve each `name_key`/`desc_key` through `en.json`, and
replace the example rows below with the full real table — one row per entry, 25–35 rows total.
The six rows below are examples in the intended voice, not a preview of the real content; only
`ACH_OEE_85` (given directly in this project's brief) is expected to survive verbatim.

## Steamworks paste format

Steamworks' Stats & Achievements admin page takes one achievement per row, three columns:

| Column | Maps to | Notes |
|---|---|---|
| **API Name** | `achievements.json` → `id` | Must be exactly the `ACH_[A-Z0-9_]+` string — this is the programmatic key `SteamBridge.set_achievement(id)` calls (`docs/ARCHITECTURE.md` §10), so it can't be reworded for style. |
| **Display Name** | `name_key` resolved via `en.json` | Player-facing title. Keep it short — long titles truncate in the unlock popup and the profile showcase. |
| **Description** | `desc_key` resolved via `en.json` | One sentence. Treat roughly 200 characters as a practical ceiling even though the field technically allows more — it gets clipped in more UI surfaces than the title does. |

An optional fourth **Hidden** column (yes/no) exists in Steamworks for achievements that
shouldn't spoil themselves in the list before unlock — none of the examples below need it, but
flag any spoiler-ish real achievement (e.g. anything tied to a specific late-game surprise) as
Hidden when the real table is built. Achievement icon art (achieved/unachieved image pairs) is a
separate Steamworks upload, not covered by this table — track it as its own task; ownership isn't
assigned to marketing (see `INTEGRATION_NOTES.md`).

## Example rows (voice reference — 6 of 25–35)

| API Name | Display Name | Description |
|---|---|---|
| `ACH_OEE_85` | World Class-ish | Hold 85% OEE — your TPM consultant weeps with joy. |
| `ACH_FIRST_BOTTLENECK_CLEARED` | Fire Fighting 101 | Clear your first bottleneck. There will be another one. There is always another one. |
| `ACH_FIRST_KAIZEN_EVENT` | Sell the Factory | Complete your first Kaizen Event. Congratulations — you now own a bigger, emptier factory. |
| `ACH_ZERO_SCRAP_5MIN` | Poka-Yoke, Baby | Run 5 straight minutes with zero scrap. Quality control has never looked more suspicious of you. |
| `ACH_FULL_LINE` | Full Line | Unlock all six stations. The gizmos practically make themselves now. |
| `ACH_LIFETIME_1M` | One Million Gizmos | Produce one million parts, lifetime. Somewhere, a warehouse manager is having a moment. |

These six deliberately span six different trigger types (`oee`, `bottleneck_cleared_count`,
`prestige_count`, `zero_scrap_seconds`, `station_unlocked`, `lifetime_parts`) so the pattern
extrapolates cleanly to the remaining vocabulary (`money_earned`, `pps`, `upgrade_count`,
`skill_count`) once the real thresholds exist.

## Voice guide for the remaining rows

- **Structure:** condition, then an em dash, then the joke — `[what you did] — [dry factory-floor
  punchline]`. Matches every example above; keep it consistent across all 25–35.
- **The joke is seasoning, not the point.** Every description should be true and useful on its
  own (a player should be able to read it and know exactly what to do) even with the joke
  subtracted — the humor rides on top of a real, accurate condition, never replaces one.
- **Respect the practice.** The jokes are about the absurdity of *idle-game numbers*, corporate
  process theater, or the player's own grind — never about lean manufacturing or its
  practitioners being wrong, stupid, or fake. TPM, Poka-Yoke, OEE, and the rest are real and
  useful; the humor is "a mouse wheel instead of a workshop," not "manufacturing is nonsense."
- **Display Names:** 1–4 words, Title Case, no exclamation points.
- **No emoji, anywhere** — matches the store page's emoji-light rule.
