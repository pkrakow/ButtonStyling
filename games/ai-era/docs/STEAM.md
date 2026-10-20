# Steam integration point

`scripts/platform/steam_service.gd` (autoload `SteamService`) is the only code that talks to Steam.

- **Without GodotSteam** (the default in this repo), it runs as a stub. Achievements and stats are kept in memory and logged as `INFO steam.init mode=stub`. The game plays normally.
- **With GodotSteam**, the GDExtension registers a `Steam` engine singleton. The service calls `steamInitEx(app_id, true)` and checks that `status == 0`, then runs `run_callbacks()` every frame, including while paused. If init fails, it logs `WARN steam.init mode=stub status=N` and keeps playing.
- **The SteamID and persona name are never read.** `segment_info()` exposes only `getAppBuildId()`, `isSteamRunningOnSteamDeck()`, and `getCurrentGameLanguage()`, which are attached to `app_start` telemetry.

## Enabling GodotSteam

1. Download the GodotSteam **GDExtension** build that matches Godot 4.7 and unpack it to `addons/godotsteam/`. It ships `steam_api64.dll` and `libsteam_api.so`, and on macOS `libsteam_api.dylib`.
2. Set `ai_era/steam/app_id` in `project.godot`. Use `480` (SpaceWar) until the real App ID exists. Do not ship `steam_appid.txt`.
3. Export as usual (`tools/export_all.sh`). No code changes are needed.

## Achievements and stats

The rules live in `scripts/platform/steam_rules.gd`, which is pure and unit-tested. Stats are written with `setStatInt` and achievements with `setAchievement`. `storeStats()` is called at run end and abandon. Create these API names in Steamworks App Admin, marking the ending achievements as **Spoiler**.

| API name | Type | Trigger |
|---|---|---|
| `ACH_FIRST_DECISION` | achievement | First decision |
| `ACH_REACH_2025` | achievement | Make a decision in 2025 or later |
| `ACH_FINISH_RUN` | achievement | Play all 32 quarters |
| `ACH_TREATY` | achievement | "Sign the treaty" response |
| `ACH_HALT` | achievement | "Halt and investigate" response |
| `ACH_END_<ENDING>` | achievement | One per ending: ABUNDANCE, CAREFUL, DIVIDE, MUDDLE, WINTER, COLLAPSE, RUNAWAY |
| `STAT_RUNS_STARTED` / `_FINISHED` / `_ABANDONED` | INT, increment-only | Run lifecycle |
| `STAT_PICKS_POLICY` / `_RESEARCH` / `_INVEST` | INT, increment-only | Card type picked |
| `STAT_MAX_YEAR` | INT, max 2030 | Furthest year reached |
| `STAT_END_<ENDING>` | INT, increment-only | Ending counts. Global totals give the ending distribution with no personal data. |

## macOS

The macOS export is unsigned. Distributing it needs Developer ID signing and notarization; set `codesign/*` and `notarization/*` in `export_presets.cfg`. Otherwise ship Windows and Linux depots only, which also covers Steam Deck.
