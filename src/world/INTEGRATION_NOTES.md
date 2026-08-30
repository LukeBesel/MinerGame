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
| `floor_grid.gdshader` | Worn concrete (real PBR maps, world-space UVs) + seam grid + dashed amber aisle strips + radial green pulse wave. |
| `belt_chevrons.gdshader` | Rubber PBR belt + emissive moving chevrons; CPU-accumulated `scroll` uniform so speed changes never jump phase. |
| `light_shaft.gdshader` | Additive skylight shaft cones (height + rim fade); works on gl_compatibility. |

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

## Art overhaul — 2026-08-30

Full visual overhaul of the hall ("too blocky / AI made" → art-directed industrial). Zero
gameplay-behavior changes: every signal, telegraph, camera fix (`toggle_walk` in `_input`,
edge-pan idle/hover guards), animation hook, and reduce_motion path is untouched.

### Lever 1 — real materials
- NEW `tools/fetch_textures.py` (python3; stdlib + PIL for recompression): downloads 7
  pinned CC0 ambientCG sets and generates 3 procedural decals. Idempotent ("up to date" on
  re-run), `--force`, `--procedural` (offline stand-ins), retrying downloader (proxy resets),
  per-set procedural fallback. Exact URLs + CC0 note in its header; rows appended to
  `assets/LICENSES.md`.
- Committed payload **2.35 MB** (budget 10 MB): Color+NormalGL 1K JPG, Roughness 512
  grayscale. Sets → roles: Concrete034 (floor, via shader), CorrugatedSteel005 (walls),
  PaintedMetal012 (machine paint, desaturated+normalized so per-station `STATION_PAINT`
  tints read true; also tinted crates/drums/bins via MultiMesh instance colors),
  MetalPlates006 (frames/plate), Metal032 (galvanized trim/rails), Rubber004 (belt, via
  shader), DiamondPlate005A (plinth tops/mezzanine/dock; source is painted blue —
  desaturated, relief lives in the normal map). Generated: hazard_stripes.jpg,
  oil_stain.png, skid_marks.png.
- `world_lib.gd` material library: `mat_pbr()` (cached, world-triplanar, roughness-tex,
  normal-tex, optional vertex-color) + named mats (`mat_machine/paint/steel_plate[_dark]/
  galv[_dark]/wall/wall_dado/diamond/rubber/safety/wood/hazard/mat_decal`). Missing textures
  degrade to flat colors (headless/parallel-safe — `tex()` guards `ResourceLoader.exists`).
  `floor_grid.gdshader` and `belt_chevrons.gdshader` now sample the concrete/rubber maps
  (world-space UVs; belt rubber tiles at exactly 1 tile per chevron_spacing so the CPU
  scroll wrap stays seamless); all texture uniforms have safe defaults.
- One `--import` run was needed after fetching (documented exception; keep runs short).

### Lever 2 — lighting & post
- Tonemap **AgX** (exposure 1.4, white 8) + adjustments contrast 1.09 / saturation 1.20;
  ambient 0.85 cool; glow hdr_threshold 1.08 intensity 0.62 (emissives only, no bloom soup);
  SSAO kept (radius 1.6 / intensity 2.6 / power 1.7); depth fog #1C2230 @ 0.0075.
- Key: shadowed DirectionalLight (#CFE0F5 @ 1.45) + 2 cool SpotLight pools under the line
  skylights (shadowless) vs warm high-bay bells over every station (omni at every 2nd
  station: 3 omnis + flicker + marker = 5 total, ≤ 8/mesh compat limit; spots are a
  separate compat bucket).
- Roof skylight panels (emissive glass + frames, ceiling render layer) with 4 additive
  cone shafts (`light_shaft.gdshader`: height fade + silhouette rim fade, blend_add,
  survives gl_compatibility) over line/back aisle only — the south pair hazed the
  management camera and was cut. Everything verified on software-GL gl_compatibility.

### Lever 3 — de-blocked machines & belts
- All six stations rebuilt as multi-part assemblies on a plated plinth (diamond top, corner
  bolt MultiMesh, edge-trim strips as chamfer illusion): press = C-frame + guide rods +
  crown/hydraulics + motor + hose run + hazard chevron; lathe = bed/ways + headstock +
  chuck jaws + tailstock + carriage + splash guard + coolant line; weld = pedestal robot
  (thicker arms, joint cylinders, dress-pack cable) + positioner clamps + wire feeder + gas
  bottle + smoked screen (aisle side only, robot silhouette kept); paint = booth + window
  band + roof plenum + exhaust stack + filter grid + grating; assembly = gantry + trolley +
  tinted small-part bin rack + mirrored arms; pack = roller bed (visible rollers MM) +
  camera pods + label printer + monitor + stretch-wrapped pallet. Every cell gains a
  control cabinet (station-tinted HMI screen — brightens when RUNNING via `_set_status`,
  LEDs, vents, conduit to the cable-tray drop), back guard rails, hazard curb, and a
  painted floor number ("01".."06", Label3D flat on slab).
- Anim hooks preserved verbatim: `_ram` (press stroke values adjusted for the taller die),
  `_spindle`, `_arm_a.._arm_d`, `_scan_bar`, sparks/mist particles.
- Belts: C-channel rails, H-frame leg stands (1 MM per belt), rotating end rollers, rubber
  PBR belt. Parts are now 3 shape variants (plate / puck / ring) as 3 MultiMeshes sharing
  the same 26-instance-per-belt cap (182 total, unchanged).
- BUGFIX found by renders: `WorldLib.apply_ghost` now also swaps **MultiMeshInstance3D**
  overrides — locked belts/stations previously left their MM pieces (legs, bolts, bins)
  solid while everything else ghosted.

### Lever 4 — environmental storytelling
All from primitives + the texture lib, aggressively MultiMeshed (every board of every
pallet in the hall is ONE draw call; same for crates, straps, drums, rims, shelving, stock,
posts, extinguishers, signs): pallet stacks + strapped crate piles (infeed, dock, south
staging), colored steel drums, cantilever rack with bar stock, cable tray + hangers + drop
conduits per station (rebuilt with the fixtures on station-count change), mezzanine along
the back wall (diamond deck, steel columns/kick, yellow handrail, stairs), wall columns,
glazed window bands, fire extinguisher points on columns, diegetic signage ("LINE 1",
"SAFETY FIRST / 312 DAYS SINCE LAST INCIDENT" board, "SHIPPING →", "RECEIVING" — decorative
English stencils, like the existing "$" tag these are environment art, not UI strings), oil
stain + tire skid alpha decals (staggered heights, no z-fighting). Forklift/fans/flicker/
dust kept (forklift repainted). Net new static draws ≈ 55 for the hall dressing (props are
~15 MultiMeshes + ~20 meshes + 8 labels + 11 decal quads); per-station adds ≈ 25–30 draws
and 3 small MultiMeshes; belts ≈ +8 each. Whole scene is still a few hundred draw calls of
tiny meshes with fully shared cached materials — no per-frame allocation added (only the
2 belt-roller spins and the HMI energy write on status change).

### Verified from software-GL renders (5 rounds, gl_compatibility @1280×720)
Dark-hall/lit-line value read; texture believability at close walk range; six distinct
silhouettes incl. full unlocked line (harness cheat); ghost + price-tag stations; "!"
bottleneck beacon, Zz/■ icons, WIP piles, scrap bins, selection/hover, chevron belts with
mixed part shapes; signage legibility; HUD-over-world sanity; walk-mode interior. Final
reference frames left in `/tmp/artshots/` (not committed, per repo policy).

### Eyeball on a real GPU (Forward+)
AgX + glow strength on emissive lamps/screens (software GL underestimates glow), SSAO
contact shading under machines/props, fog density at far zoom, shaft cone alpha (raise
`light_shaft.gdshader strength` to ~0.12 if too faint with real blending), normal-map
strength on the floor at grazing angles, anisotropic filtering on the aisle.

### Validation at hand-off
- `--check-only`: clean on all 5 world scripts (documented autoload false-positives only).
- Full suite: **155 passed / 0 failed** (`run_tests.gd`, includes other agents' new tests).
- `BNK_SMOKE=1` headless boot: `BNK_SMOKE_OK`, zero script errors.
- `python3 tools/fetch_textures.py` twice: idempotent, `du -sh assets/textures` = 2.6M.
