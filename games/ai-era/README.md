# Runtime: Takeoff (working title)

A short pixel-art sim in the spirit of SimCity. You don't build a city: you steer AI from the fall 2022 chatbot launch through 2030 Q3, one quarter per turn, and watch jobs, prosperity, unrest, compute, and population shift across six world regions.

- **One run** is 32 quarters, typically 15–25 minutes. It ends early if unrest boils over or AI capability far outpaces safety.
- **Each turn** you pick one of three cards: a policy, a research direction, or an investment. Random events fire, and some are dilemmas with two responses.
- **Seeded:** the seed is shown in the HUD and on the end screen. The same seed with the same choices replays the same run.
- **Seven endings**, each with an epilogue, a summary, and charts.
- **No accounts, no multiplayer, no real companies or people.**

## Why Godot 4

Godot 4.7 exports Windows, macOS, and Linux from one Linux machine with official templates. It has a mature Steamworks binding (GodotSteam GDExtension) that needs no custom engine build, a small runtime (~70 MB), and a free MIT license. GDScript keeps the simulation testable headless. The compatibility renderer runs on older GPUs and Steam Deck.

## Run it

```bash
# Godot 4.7.x on PATH as `godot`
cd games/ai-era
godot --path .                                     # play
godot --headless --path . -s res://tests/run_tests.gd   # unit tests (exit code 1 on failure)
godot --headless --path . -s res://tools/balance.gd -- 200  # ending distribution per scripted strategy
./tools/export_all.sh                              # tests + Windows/Linux/macOS builds into build/
```

Dev flags, passed after `--`: `--autoplay` picks random options, `--seed=<n>` fixes the seed, and `--capture=<dir>` saves screenshots of each screen. With `--capture`, the game quits after the end screen.

## Controls

- `1`–`3`: pick an option. Arrow keys and Enter also work, and the focused option has a thick yellow outline.
- `P`, `J`, `U`, `C`, `A`: switch the map between prosperity, jobs, unrest, compute, and AI adoption.
- `Esc`: pause or resume, or close a panel. `Tab` moves focus in menus.

## Accessibility

The map never relies on color alone. Value is shown by brightness, by how many sub-squares are filled in, and by a numeric label with a ▲/▼ trend for each region. Stat changes show an arrow and a signed number. Settings include an interface size option (100/125/150%), reduce motion, and fullscreen. Buttons have accessibility names and tooltips. Options ignore input for 350 ms after they appear, which prevents accidental double picks.

## Telemetry and privacy

Play data is **opt-in**. A first-launch screen offers two equal choices, and there is a toggle in Settings. Turning it off deletes local play data. Events go to local JSONL and an offline queue, then upload in batches to a pluggable HTTP endpoint. The default endpoint is a no-op. See [docs/EVENT_SCHEMA.md](docs/EVENT_SCHEMA.md) and [docs/PRIVACY.md](docs/PRIVACY.md). The failure log is `user://logs/runtime-takeoff.log`, one `TIMESTAMP LEVEL component key=value` line per entry, so `grep " ERROR "` finds real failures.

## Steam

`SteamService` is a stub until GodotSteam is dropped into `addons/godotsteam/`. Achievements and stats are already wired. See [docs/STEAM.md](docs/STEAM.md).

## Layout

```
scripts/sim/        simulation.gd (deterministic core), sim_data.gd (regions, cards, events, endings), strategies.gd (scripted players)
scripts/telemetry/  telemetry_core.gd (events, JSONL, queue, retry), sinks.gd (Null/Memory/Http), telemetry_node.gd (autoload)
scripts/platform/   steam_service.gd (autoload, stub fallback), steam_rules.gd (achievement/stat rules)
scripts/core/       game_log.gd (grep-friendly log), settings.gd (autoload)
scripts/ui/         main.gd (screens, HUD, input, telemetry calls), world_map.gd, mini_chart.gd, ui_theme.gd
tests/              run_tests.gd + test_*.gd (no addon needed)
tools/              balance.gd, export_all.sh
```
