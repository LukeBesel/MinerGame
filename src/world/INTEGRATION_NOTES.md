# World layer — integration notes

Owner: world agent. Everything under `src/world/` is built in code at runtime; the only scene
file is the 2-entry `factory_world.tscn` (Node3D "FactoryWorld" + script), instanced by
`src/core/main.gd` before the HUD.

## Files

| File | Role |
|---|---|
| `factory_world.tscn` | Fixed scene path (§4). Root `Node3D` "FactoryWorld" + `factory_world.gd`; whole tree built in `_ready()`. |
| `factory_world.gd` | Environment (WorldEnvironment, lights, floor/walls/trusses), builds/rebuilds the line, bottleneck marker, green cleared-pulse, selection ring, ambient life, owns the camera rig. |
| `station_view.gd` | One machine per station: distinct silhouette per pinned id, status beacon + icons, WIP pile, scrap bin, ghost/locked state, cycle animation from `progress`. |
| `conveyor_view.gd` | Belt segment: chevron shader scrolling ∝ upstream throughput, MultiMesh parts (density ∝ flow, capped). |
| `camera_rig.gd` | Orbit camera (default) + Gemba Walk (CharacterBody3D); click/hover raycasts. |
| `world_lib.gd` | Palette/layout constants, build-once mesh & material caches, ghost swap, settings access. |
| `floor_grid.gdshader` | Worn concrete + seam grid + dashed amber aisle strips + radial green pulse wave. |
| `belt_chevrons.gdshader` | Emissive moving chevrons; CPU-accumulated `scroll` uniform so speed changes never jump phase. |

## Runtime node tree (built in `_ready`)

```
FactoryWorld (Node3D, factory_world.tscn)
├─ WorldEnv (WorldEnvironment: filmic tonemap, glow, SSAO*, depth fog, adjustments)
├─ Skylight (DirectionalLight3D, shadows)
├─ Floor (MeshInstance3D + floor_grid.gdshader) / FloorBody (StaticBody3D, physics layer 1)
├─ walls + skylight-strip panels + Trusses (MultiMeshInstance3D, render layer 2 = "ceiling")
├─ Fixtures (per-station hanging lamps; OmniLight3D at every 2nd station — stays ≤ 8 lights
│   per mesh for gl_compatibility)
├─ Infeed / Dock (line dressing), Fan_0/1 + Forklift + FlickerFixture + Dust (ambient life)
├─ BottleneckMarker (rotating/pulsing red beacon + "!" Label3D + OmniLight3D — ONE traveling
│   node, tween-slides between stations)
├─ PulseRing / ClearBurst (bottleneck_cleared FX) · SelectionRing
├─ Line
│   ├─ Station_<i>_<id> (station_view.gd) ×N at x = i·7, z = 0
│   │   ├─ Body (silhouette meshes; ghost material override while locked)
│   │   ├─ Beacon (post + status LED + icon Label3D), name Label3D, price Label3D (locked)
│   │   ├─ WipPile (MultiMesh, ≤12), ScrapBin (fill scales with scrap share)
│   │   └─ Pick (StaticBody3D, physics layer 2, meta `station_index`)
│   └─ Conveyor ×(N+1): infeed + between stations + outfeed
└─ CameraRig (camera_rig.gd)
    ├─ OrbitCamera (default current)
    └─ WalkBody (CharacterBody3D, capsule) → Head → WalkCamera
```
\* SSAO/fog are Forward+; on `gl_compatibility` (web) they degrade silently (verified — only a
console warning from the rendering server, not a script error).

## Signals consumed

- `sim_stats` — drives everything each 100 ms: per-station view dicts (status, progress,
  throughput, buffers, scrap, unlocked, is_bottleneck), conveyor flow, marker safety-net.
  Station-count mismatch triggers a full line rebuild **from the passed dict**.
- `game_reset`, `load_completed` — full line rebuild (from `Game.get_stats_snapshot()`; empty
  factory when `Game.sim == null`).
- `bottleneck_changed(new, old)` — marker tween-slides (0.5 s cubic; instant under
  reduce_motion or when previously hidden).
- `bottleneck_cleared(station)` — green burst at the station, marker flashes green ~0.55 s,
  floor-shader wave + expanding ring sweep outward (skipped under reduce_motion; burst kept).
- `station_upgraded` — accent flash + scale pop on that station (pop skipped under reduce_motion).
- `station_unlocked` — pop + re-frame orbit camera to the new unlocked extent.
- `station_selected` — amber floor ring under the station (world reacts to panel clicks too).
- `settings_changed` — re-caches `reduce_motion` / `camera_sensitivity`.

## Signals emitted

- `station_selected(index)` — LMB click in orbit mode (click, not drag), LMB or `interact`(E)
  in walk mode. Raycast against physics layer 2 pick boxes; **locked stations are clickable**
  (so the UI can show the unlock panel).
- `camera_mode_changed(SimTypes.CAMERA_ORBIT|CAMERA_WALK)` — on every mode switch. No initial
  emission at boot; HUD should assume ORBIT until told otherwise.

## Camera controls (as built)

Orbit (default): RMB-drag orbit, wheel zoom (6–48 m), MMB-drag pan, edge pan (16 px margins),
smoothed lerp, auto-frames unlocked extent on rebuild/unlock (user pan/zoom freely afterwards).
Tab (`toggle_walk`) enters Gemba Walk: mouse-captured look, WASD (`move_*`), head bob (off under
reduce_motion), collides with floor + machines, hard-clamped to the floor rect. Tab or Esc
(`pause_menu`, consumed) returns to orbit and releases the mouse.
Note for UI: in walk mode Esc exits walk first — a pause menu should open on the *second* Esc.

## Defensive behavior (parallel-safe)

- `Game.get("sim") == null` / missing methods → attractive empty factory; rebuilds when
  `load_completed`/`game_reset`/first `sim_stats` arrives.
- `SettingsService` read via `get()` with fallbacks (`reduce_motion` false,
  `camera_sensitivity` 1.0, `number_format` "suffix" for the ghost price tag).
- All station-view dict fields read with `.get()` + defaults; `unlock_cost` formatted only if
  it quacks like BigNum. Unknown station ids get a generic silhouette.
- Camera rig registers input actions itself if Main hasn't yet (direct-scene dev runs).

## Performance notes

- All static materials/meshes come from `world_lib.gd` build-once caches; per-instance
  materials (beacons, accents, marker, belts) are created once at build time. No material or
  node allocation per frame (tweens only on events).
- Parts are MultiMesh: ≤ 26 per belt × 7 belts = 182 instances (< 200 cap); WIP piles ≤ 12
  each. Above the cap the belt reads as a continuous stream (per §8 / balance.visual intent).
- Per-frame cost is O(stations + conveyors): phase math, ≤ 8 shader-param sets, transform
  writes for visible part slots only.
- Ceiling clutter (trusses/fans) lives on render layer 2; the orbit camera culls it while
  above y ≈ 6.8 so beams never slice the management view — the walk camera always renders it.

## Visual verification done (software-GL captures, gl_compatibility)

Verified from rendered frames: line + ghost stations + prices, status icons (Zz/■), bottleneck
"!" + red light pool, selection ring, chevron belts + riding parts, WIP piles/scrap bins,
green cleared pulse (ring + wave + burst + green marker flash), marker slide, walk-mode view
with ceiling/trusses/fans, forklift, skylight strips, full real-boot with live sim + HUD
(world and HUD agreed on the bottleneck station). Things integration should eyeball on a real
GPU (Forward+): glow/bloom strength on emissives, SSAO contact shading, fog density at far zoom.

## Validation status (at hand-off)

- `--check-only` on all 5 world scripts: clean (only the documented autoload false-positives).
- Full boot smoke (`BNK_SMOKE=1`, headless): `BNK_SMOKE_OK`, no world errors — with the live
  sim once data landed.
- Test suite: world adds no tests and does not affect the run. At last run: 118 passed /
  6 failed — all failures in sim-agent economy/pacing tests (`test_effects`, `test_milestones`,
  `test_offline`, `test_pacing`), pure-sim files unrelated to `src/world` (they were mid-flight
  while parallel agents tuned balance).

## Small contract-adjacent notes

- World shows station names from the (already localized) `name` field of station views and a
  "$ <BigNum>" price tag; no other user-facing strings are hard-coded (signage is iconographic).
- Floor/walls are sized for the pinned 6-station line (constants in `world_lib.gd`). More than
  ~7 stations would outgrow the shell — bump `FLOOR_MAX_X` if the data ever grows.
- Randomness in this layer is cosmetic only (flicker timing); all sim-driven motion is
  deterministic from `sim_stats`.
