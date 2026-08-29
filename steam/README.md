# Steam packaging — Bottleneck

Everything needed to take a Godot export through Steamworks, plus the checklist for a healthy
Steam Deck experience. This file only describes *process* — the game code itself never requires
Steam to be present (see `src/steam/steam_bridge.gd`: every Steam call is a safe no-op without
it, and that is the actual shipped behavior of every build this repo can currently produce, since
no GodotSteam GDExtension binary is vendored here yet).

## 1. Steamworks app setup (one-time, per app)

1. Register the app at https://partner.steamgames.com (App Admin -> New App). Note the numeric
   **App ID** Steam assigns.
2. Under **Installations & Depots**, create one depot per shipped platform (Windows, Linux,
   macOS). Note each **Depot ID**.
3. Replace every `APP_ID` / `DEPOT_ID_WINDOWS` / `DEPOT_ID_LINUX` / `DEPOT_ID_MACOS` placeholder
   in:
   - `steam/app_build.vdf`
   - `steam/depot_build_windows.vdf`, `steam/depot_build_linux.vdf`, `steam/depot_build_macos.vdf`
   - `src/data/steam.json` (`"app_id"`) — this is the value `SteamBridge` reads at runtime to
     initialize the SDK. The shipped `480` is Valve's public "Spacewar" test app id — safe to
     build and test against, must never ship to players.
4. Under **Steam Cloud**, enable cloud saves — see §4 for the exact path to configure.
5. Under **Stats & Achievements**, create one achievement per row of
   `marketing/steamworks_achievements.md` (owned by the marketing agent — that file is the single
   source of truth for achievement ids/names/descriptions/icons). Each `id` in
   `src/data/achievements.json` (pattern `^ACH_[A-Z0-9_]+$`) must match the *API Name* entered
   here exactly — `SteamBridge.set_achievement(id)` passes that id straight through.

## 2. Building + uploading with steamcmd

Prereqs: a depot-upload-enabled Steam account with Steam Guard set up for CLI login, and
`steamcmd` installed (https://developer.valvesoftware.com/wiki/SteamCMD).

```bash
# 1. Produce the platform builds (see ../build.sh / ../build.ps1) -- populates ../builds/.
cd ..
./build.sh windows linux macos
cd steam

# 2. Upload via steamcmd, from this steam/ directory:
steamcmd +login <your_steam_account> \
  +run_app_build "$(pwd)/app_build.vdf" \
  +quit
```

`run_app_build` reads `app_build.vdf`, which in turn reads each `depot_build_*.vdf`; every
depot's `contentroot` already points at the matching `builds/<platform>/` output directory from
`build.sh`/`build.ps1`, so no extra flags are needed once the placeholders are filled in. A build
lands as a private (unlisted) build on the Steamworks backend by default (`app_build.vdf`'s
`setlive` is empty) — promote it to a branch from the web dashboard, or set `"setlive" "default"`
(or a beta branch name) in `app_build.vdf` to publish straight from the CLI.

## 3. Steam Deck checklist

- **Controller navigation** — every interactive HUD element must be reachable by D-pad/stick
  focus traversal, not just mouse/touch. Verify with an actual controller (or Steam Input's
  on-screen cursor as a fallback) before certifying; this is a UI-layer wiring concern
  (`src/ui/`), not something the save/Steam layer can verify on its own.
- **Legibility at 1280x800** — the Deck's panel is 1280x800, which is *taller* than the
  1280x720 baseline resolution the UI targets (docs/ARCHITECTURE.md §12 already pins 1280x800 as
  a target range, alongside 1280x720 through 4K) — extra vertical room, not less, but re-check
  panel anchoring so nothing floats oddly or leaves dead space at the taller aspect.
- **Suspend/resume** — there is no special suspend hook. Deck suspend/resume is covered by the
  regular autosave cadence (`balance.autosave_seconds`, 30s default) plus the quit-safe save on
  `NOTIFICATION_WM_CLOSE_REQUEST` in `src/save/save_manager.gd`. Worst case on an abrupt suspend
  is losing up to one autosave interval of progress — never a corrupt save, since a save write is
  always a full-file rewrite of `save_0.json` (never a partial in-place edit), and the two older
  rotation backups are untouched by a failed/interrupted write.
- **Default input mapping** — confirm the Deck's default controller config maps sensibly
  out of the box against the actions registered in `src/core/input_setup.gd`; ship a documented
  Steam Input controller config once GodotSteam is wired for real (§6).
- A native Linux x86_64 build is shipped, so Proton compatibility is not a concern for Deck —
  it runs the same binary as desktop Linux.

## 4. Cloud save configuration

The game always writes saves to Godot's `user://` directory, which Steam Cloud can sync verbatim
— no extra code is needed to make paths Cloud-safe, Godot already gives every platform a distinct
sandboxed user-data directory.

- **Path to sync**: `saves/*.json`, relative to the Cloud root you configure in the Steamworks
  dashboard. Point that root at the platform's Godot user-data directory for this app, e.g.:
  - Linux: `~/.local/share/godot/app_userdata/Bottleneck/saves/`
  - Windows: `%APPDATA%\Godot\app_userdata\Bottleneck\saves\`
  - macOS: `~/Library/Application Support/Godot/app_userdata/Bottleneck/saves/`
- Optionally also sync `settings.json` (same root, one level up from `saves/`) so audio/
  accessibility preferences follow the player between machines. Off by default in this slice —
  volume/accessibility settings are arguably per-machine more often than not — revisit if
  playtesting shows players expect it to travel.

### Cloud-conflict prompt

`SteamBridge.resolve_cloud_conflict(local, cloud)` (in `src/steam/steam_bridge.gd`) takes two
summaries — `{"saved_at_unix": int, "lifetime_parts": float}` — and returns one of:

- **`"local"` / `"cloud"`** — the two saves agree closely enough (the newer-by-timestamp save is
  also the same-or-more progressed) that picking it silently is safe. No prompt shown.
- **`"ask"`** — the *older*-by-timestamp save has meaningfully *more* `lifetime_parts` than the
  newer one (real divergent play on a second machine that hasn't synced yet, or a rollback).
  Picking either side silently risks discarding real progress, so the UI must show a blocking
  dialog before either save is touched:

  > **Cloud save conflict**
  > Your local save (🖥 *\<local time\>*, *\<local lifetime parts\>* parts made) differs from
  > your Steam Cloud save (☁ *\<cloud time\>*, *\<cloud lifetime parts\>* parts made).
  >
  > **[ Keep this device's save ]**   **[ Keep Steam Cloud's save ]**
  >
  > Whichever you don't pick is kept as a backup in `user://saves/`, not deleted.

  Implementation note: this dialog does not exist yet — no `src/ui/` owner has built it, and
  `SaveManager.boot_load()` does not call `resolve_cloud_conflict()` yet either, since there is
  no real Steam Cloud session to read a "cloud" summary from without the GodotSteam binary (see
  `SteamBridge.check_cloud_conflict()` for the documented wiring point). `SteamBridge` only owns
  the decision + which save wins; the UI agent owns rendering the actual dialog once this is
  activated for real.

## 5. macOS signing & notarization

Godot's raw macOS export is an unsigned `.app` bundle; Steam's own upload doesn't require signing,
but Gatekeeper on modern macOS blocks launching an unsigned/unnotarized app outside Steam's own
auto-update path, so sign + notarize before any public build:

1. Requires an active Apple Developer Program membership (US$99/yr) for a "Developer ID
   Application" certificate.
2. Sign:
   `codesign --deep --force --options runtime --sign "Developer ID Application: <you>" Bottleneck.app`
3. Notarize:
   `xcrun notarytool submit Bottleneck.zip --apple-id <id> --team-id <team> --password <app-specific-password> --wait`
   then `xcrun stapler staple Bottleneck.app`.
4. `build.sh` / `build.ps1` do **not** sign automatically — that needs secrets/certificates that
   don't belong in this repo. Run signing as a manual (or CI-secret-gated) step after export,
   before the macOS depot upload in §2.

## 6. What's still a placeholder

- `src/data/steam.json`'s `app_id` (480 = Spacewar test app) and every `APP_ID`/`DEPOT_ID_*` in
  this folder's `.vdf` files — swap in the real values from §1 once the Steamworks app exists.
- `SteamBridge` only talks to GodotSteam through TODO-marked stubs (see
  `src/steam/steam_bridge.gd`) — there is no GodotSteam GDExtension binary in this repo, so
  `available` is `false` in every build this repo can currently produce. That's by design: the
  game must be identical without Steam (itch/web build). See `src/save/INTEGRATION_NOTES.md` for
  the exact wiring steps once the GodotSteam binary is added to the project.
