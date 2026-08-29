# Steamworks Achievements — Paste List

## What this file is

The complete, paste-ready achievement list for the Steamworks Stats & Achievements admin page —
**generated from `src/data/achievements.json`** (the runtime source of truth that
`SteamBridge.set_achievement(id)` fires against) with names/descriptions resolved through
`src/data/locale/en.json`. 30 achievements, in file order (Steamworks displays list order, and
the order reads as the natural unlock narrative — don't alphabetize). If `achievements.json` or
the locale changes, regenerate this table rather than editing rows by hand.

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

## The paste table (30 rows, file order)

| API Name | Display Name | Description |
|---|---|---|
| `ACH_FIRST_PART` | Day One | Ship your first gizmo. Frame the invoice. |
| `ACH_PARTS_100` | Batch of a Hundred | Make 100 parts. The line is officially a line. |
| `ACH_PARTS_10K` | Ten Thousand Strong | Make 10,000 parts. |
| `ACH_PARTS_1M` | Gizmo Millionaire | Make 1,000,000 parts. Somewhere, a warehouse groans. |
| `ACH_PARTS_100M` | Heavy Industry | Make 100,000,000 parts. You are a supply chain now. |
| `ACH_MONEY_1K` | First Grand | Earn 1,000 lifetime. |
| `ACH_MONEY_100K` | Six Figures | Earn 100,000 lifetime. |
| `ACH_MONEY_10M` | Serious Revenue | Earn 10,000,000 lifetime. Accounting sends a fruit basket. |
| `ACH_PPS_1` | One a Second | Reach 1 part per second. |
| `ACH_PPS_10` | Double Digits | Reach 10 parts per second. |
| `ACH_PPS_100` | The Firehose | Reach 100 parts per second. Please stand clear of the chute. |
| `ACH_OEE_85` | The 85% Club | Hold OEE at 85% — the number plant managers frame on the wall. |
| `ACH_ZERO_SCRAP_HOUR` | Golden Hour | Run a full hour without scrapping a single part. |
| `ACH_HERBIE` | Finding Herbie | Clear 3 bottlenecks. Every line has a Herbie. (Read The Goal.) |
| `ACH_WHACK_A_MOLE` | Whack-a-Mole | Clear 25 bottlenecks. The constraint always moves. Always. |
| `ACH_FLOW_STATE` | Flow State | Clear 100 bottlenecks. |
| `ACH_CONSTRAINT_WHISPERER` | Constraint Whisperer | Clear 500 bottlenecks. You can hear the line thinking. |
| `ACH_FRESH_COAT` | Fresh Coat | Bring the Paint Booth online. |
| `ACH_SOME_ASSEMBLY` | Some Assembly Required | Bring the Assembly Cell online. |
| `ACH_SHIP_IT` | Ship It | Bring QA & Packout online. The whole line, end to end. |
| `ACH_UPGRADES_25` | Tinkerer | Install 25 upgrades. |
| `ACH_UPGRADES_100` | Machine Shop Regular | Install 100 upgrades. The vendors know your coffee order. |
| `ACH_UPGRADES_500` | Capital Expenditure | Install 500 upgrades. |
| `ACH_FIRST_SKILL` | Student of Flow | Learn your first lean skill. |
| `ACH_SKILLS_15` | Lean Practitioner | Learn 15 lean skills. |
| `ACH_SKILLS_ALL` | Sensei | Learn every skill on the tree. Now teach someone else. |
| `ACH_KAIZEN_1` | Under New Management | Hold your first Kaizen Event. |
| `ACH_KAIZEN_3` | Serial Improver | Hold 3 Kaizen Events. |
| `ACH_KAIZEN_7` | Change Is the Only Constant | Hold 7 Kaizen Events. |
| `ACH_WORLD_CLASS` | World Class | Hold 15 Kaizen Events. Toyota would like a word. A kind one. |

None of these need the optional **Hidden** flag today — nothing here spoils a late-game surprise;
revisit if a future content drop adds one. Achievement icon art (achieved/unachieved pairs) is a
separate Steamworks upload — tracked as its own task, not owned by marketing.

## Voice guide (for future additions)

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
