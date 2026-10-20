# Runtime: Takeoff (working title)

An iPhone game, portrait and touch-first (Android later). A short pixel-art sim in the spirit of SimCity. You don't build a city: you steer AI from the fall 2022 chatbot launch through 2030 Q3, one quarter per turn, and watch jobs, prosperity, unrest, compute, and population shift across six world regions.

- **One run** is 32 quarters, typically 15–25 minutes. It ends early if unrest boils over or AI capability far outpaces safety.
- **Each turn** you pick one of three cards: a policy, a research direction, or an investment. Random events fire, and some are dilemmas with two responses.
- **Seeded:** the seed is shown in the HUD and on the end screen. The same seed with the same choices replays the same run.
- **Seven endings**, each with an epilogue, a summary, and charts. The **Endings** screen on the title keeps a local collection of which endings and eras you have reached, with hints for the ones you haven't.
- **Short-session friendly:** the run saves after every decision. Leaving the app pauses it, and **Continue** on the title screen picks up where you left off, even after the OS kills the app.
- **No accounts, no multiplayer, no real companies or people.**

## Why Godot 4

Godot 4.7 exports an iOS Xcode project from Linux with official templates, and Android from the same project later. It has a small runtime and a free MIT license. GDScript keeps the simulation testable headless, and the compatibility renderer runs on older iPhones.

## Run it

```bash
# Godot 4.7.x on PATH as `godot`
cd games/ai-era
godot --path .                                     # play
godot --headless --path . -s res://tests/run_tests.gd   # unit tests (exit code 1 on failure)
godot --headless --path . -s res://tools/balance.gd -- 200  # ending distribution per scripted strategy
./tools/export_all.sh                              # tests + iOS Xcode project (build/ios) + Linux playtest build
godot --path . --resolution 390x844 -- --sim-safe-area=59,34 --dev-keys   # phone-sized window with a simulated notch
```

Dev flags, passed after `--`: `--autoplay` picks random options, `--seed=<n>` fixes the seed, and `--capture=<dir>` saves screenshots of each screen. With `--capture`, the game quits after the end screen. `--sim-safe-area=<top>,<bottom>` draws a Dynamic Island and home indicator and insets the layout like an iPhone. `--dev-keys` makes F8 simulate the app going to the background and back.

To ship to TestFlight, see [docs/IOS_BUILD.md](docs/IOS_BUILD.md).

## Controls

- **Touch:** tap an option to pick it. Tap a map overlay button (Prosperity, Jobs, Unrest, Compute, AI use) to switch the map, and tap a region for its details. **Pause** is in the top bar. Every tap target is at least 44 pt, and the layout stays inside the safe area.
- **Keyboard** (hardware keyboard, desktop): `1`–`3` pick an option, and arrow keys plus Enter also work. `P`, `J`, `U`, `C`, `A` switch the map overlay. `Esc` pauses or resumes, or closes a panel. `Tab` moves focus.

## Accessibility

The map never relies on color alone. Value is shown by brightness, by how many sub-squares are filled in, and by a numeric label with a ▲/▼ trend for each region. Stat changes show an arrow and a signed number. Settings include an interface size option (100/115/130%), reduce motion, and, on desktop, fullscreen. Buttons have accessibility names and tooltips. Options ignore input for 350 ms after they appear, which prevents accidental double picks.

## Telemetry and privacy

Play data is **opt-in**. There is no IDFA and no tracking, so the game has no App Tracking Transparency prompt. A first-launch screen offers two equal choices, and there is a toggle in Settings. Turning it off deletes local play data. Events go to local JSONL and an offline queue, then upload in batches to a pluggable HTTP endpoint. The default endpoint is a no-op. See [docs/EVENT_SCHEMA.md](docs/EVENT_SCHEMA.md) and [docs/PRIVACY.md](docs/PRIVACY.md). The failure log is `user://logs/runtime-takeoff.log`, one `TIMESTAMP LEVEL component key=value` line per entry, so `grep " ERROR "` finds real failures. The `ai_era/telemetry/id_scope` setting switches between a per-install ID (default) and per-run IDs only. It changes the App Store privacy label; see the table at the end of PRIVACY.md.

## Platform services

The `Platform` autoload picks a backend: a Game Center stub on iOS (live once the optional plugin is added, see [docs/IOS_BUILD.md](docs/IOS_BUILD.md#optional-game-center)), Steam on desktop when enabled, and otherwise a plain stub. Steam is on hold. Its code stays in the repo but is left out of the iOS build ([docs/STEAM.md](docs/STEAM.md)).

## Layout

```
scripts/sim/        simulation.gd (deterministic core), sim_data.gd (regions, cards, events, endings), strategies.gd (scripted players)
scripts/telemetry/  telemetry_core.gd (events, JSONL, queue, retry), sinks.gd (Null/Memory/Http), telemetry_node.gd (autoload)
scripts/platform/   platform_services.gd (autoload Platform), achievement_service.gd (stub base), game_center_service.gd, steam_service.gd (not in iOS build), achievement_rules.gd
scripts/core/       game_log.gd (grep-friendly log), settings.gd (autoload), run_save.gd (save/resume), collection.gd (endings found)
scripts/ui/         main.gd (screens, HUD, input, telemetry calls), world_map.gd, mini_chart.gd, ui_theme.gd
tests/              run_tests.gd + test_*.gd (no addon needed)
tools/              balance.gd, export_all.sh, make_icon.gd (app icon)
docs/               EVENT_SCHEMA.md, PRIVACY.md (incl. App Store label), IOS_BUILD.md, STEAM.md
```
