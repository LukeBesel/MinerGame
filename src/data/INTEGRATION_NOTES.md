# Data & Balance — Integration Notes

Owner: data agent. Everything under `src/data/` plus `tests/test_data.gd`.

## Content counts

| Table | Count | Notes |
|---|---|---|
| stations.json | 6 stations × 4 upgrade tracks | pinned ids/order; press/lathe/weld start unlocked |
| skill_tree.json | **51 nodes** (44–60 allowed) | flow 10, reliability 10, quality 10, speed 10, people 11; every branch spans rows 0–8 |
| milestones.json | **24 milestones**, 39 KP total | 26 KP reachable pre-prestige |
| achievements.json | **30 achievements** | all ids `^ACH_[A-Z0-9_]+$`; `ACH_SKILLS_ALL` threshold = 51 = node count (test-enforced) |
| hints.json | **10 hints** | array pre-sorted by `priority` descending |
| locale/en.json | **290 keys** | includes 80 `ui.*` keys; every `*_key` in every table resolves (validator- and test-enforced) |
| steam.json | `app_id` 480 placeholder | consumed by `src/steam/steam_bridge.gd` per §10 |

## Loader contract (`loader.gd`, autoload `Data`)

- `static load_all() -> Dictionary` — db keys `stations, skills, milestones, achievements,
  balance, hints` **plus `locale`** (the parsed en.json, so `validate` is a pure function of db).
- Cost normalization (verified against the sim engine's consumption):
  - `unlock_cost` → BigNum dict `{"m": float, "e": int}` (engine reads it via `Milestones.to_bignum` / `BigNum.from_dict`).
  - upgrade `base_cost` → **plain float** (the engine's cost curves do `float(u.get("base_cost"))`;
    a `{m,e}` dict here silently breaks `get_upgrade_view` — found the hard way, fixed).
  - trigger values: `station_unlocked` → String station id; every other trigger → float.
  - `row/cost/kp/max_level/capacity/operator_count/priority` → int, everything else numeric → float.
- `static validate(db) -> Array[String]` — checks: every `*_key` resolves in en.json; pinned
  station ids/order and exactly the 4 pinned upgrade tracks; growth ∈ [1.05, 1.2]; effect/trigger/
  hint-cond types ⊆ pinned vocabularies (incl. stat/scope/op legality and `station:<id>` scopes);
  44–60 skill nodes; prereqs exist, same-branch, strictly earlier row; 28–32 achievements with the
  Steam id regex; unique ids everywhere; balance pinned keys present and sane; hints sorted.
- Instance: `_ready()` fills `Data.db`, `push_error`s each validation failure;
  `Data.station(id)` / `Data.skill(id)` lookups return `{}` for unknown ids.

## Balance rationale (how the numbers were tuned)

- **Tuned against the real sim, not just a model.** Final pacing was verified by running the sim
  agent's greedy autoplayer on the actual `SimEngine` (probe at multiple horizons). The pinned
  gate `tests/test_pacing.gd :: test_pacing_first_prestige_on_real_data` passes: **first prestige
  at 29.4 min**, inside `pacing.first_prestige_target_minutes [25, 50]`, with 45 distinct progress
  events in the first 15 min (≥ 6 required).
- **Opening 20 seconds:** starting_money 15 vs lathe speed at 3 buys ~3 upgrades at boot; the
  slowest starter (lathe, 0.316 eff pps) is the first bottleneck by construction. Starter base
  throughputs are staggered ~16/22% (lathe 0.316 / weld 0.366 / press 0.446), so every 2–4
  purchases genuinely move the constraint — the model shows 30+ bottleneck moves in the first
  10 minutes and the constraint touching all of press/lathe/weld (and paint once unlocked).
- **Value-add pricing discovered and balanced for:** the engine sells at
  `price_per_part × price_mult × unlocked_station_count`. This makes unlocks real revenue
  decisions (+1/k price per part) even though a fresh station briefly becomes the new bottleneck
  (its base throughput is set at ~55–75% of the expected line rate at its unlock window, so
  clearing it is a quick, satisfying rush). Unlock costs sized to value-add wallets:
  paint 250 (~4–6 min), assembly 3200 (~12–16 min), pack 30000 (~25–35 min) for a human;
  the greedy bot skips unlocks entirely (see quirks) so the enforceable window is unaffected.
- **Growth curves:** speed 1.08–1.10 (×0.92 cycle/level), machine 1.12–1.15 (+1 capacity),
  tooling 1.10–1.12 (quality toward-one 0.10), smed 1.09–1.11 (×0.88 changeover) — all inside
  the 1.07–1.15 design band. Speed is the long-run sustainable track; capacity is the bumpy
  mid-game accelerant; tooling/smed monetize the quality/availability terms of the pinned formula.
- **KP economy:** milestones drip 39 KP one-time (26 pre-prestige — comfortably 6–10 early nodes
  at 1–3 KP); the deep tree (249 KP total) is a long-haul goal funded by `kp_passive_per_min`
  nodes (0.5/min fully stacked) and persists through prestige. First prestige grants 2 CIP
  (+20% line) at the 220k-part gate (`floor(sqrt(220000/50000)) = 2`), plus retained skills and
  `institutional_memory` starting cash — prestige never feels like starting over (research pillar).

## Deviations

None from the pinned §7 schemas or vocabularies. Extra (allowed) additions only:
- `db["locale"]` extra key in the loaded db (see above).
- `upgrade.<track>.tip` locale keys exist for tooltip one-liners (UI may use or ignore).
- `steam.json` kept with its externally-added `_note` field.

## Quirks & expectations for other agents

- **World agent:** the flow-branch row-0 skill `powered_conveyors` emits
  `unlock_feature {"feature": "conveyor_speed_visual"}` — the early conveyor-speed visual unlock.
- **UI agent (hints):** array is pre-sorted by `priority` desc (higher = more urgent; ties keep
  file order). `cond.value` is a numeric threshold for `*_seconds`/`kp_unspent` and boolean `true`
  for `affordable_bottleneck_upgrade`/`can_prestige`/`always`. `cooldown_s` is per-hint.
- **Sim agent:** the autoplayer never buys unlocks on this data (greedy immediate Δrps rejects the
  temporary dip; a human accepts it for the price bump + milestone KP). Pacing test still passes;
  if the bot later learns to unlock, first prestige moves ~3–6 min earlier — still inside [25, 50].
- **`ACH_ZERO_SCRAP_HOUR`** (zero_scrap_seconds 3600) assumes "no whole scrap unit produced in the
  window" — reachable only with deep quality investment (tooling toward-one + quality skills).
- OEE milestones 0.5/0.7 fire during the first minutes (line warm-up crossing), by design — they
  are tutorial-drip beats; `ACH_OEE_85` (the real-world world-class number) is the earned one.

## Final test summary

`BNK_TEST_FILTER=data`: **14/14 PASS (622 asserts)** · full suite at time of writing:
**124 passed / 0 failed (1370 asserts, ~9 s)** including `test_bignum` and the sim agent's
pacing gate on this data (`prestige_time=1765 s`, target 1500–3000 s).
