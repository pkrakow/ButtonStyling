# Telemetry event schema (v1)

Events are recorded only after the player opts in. Each event is one JSON object per line in
`user://telemetry/events-YYYY-MM-DD.jsonl`, and also in `user://telemetry/queue.jsonl` until it has been uploaded.
On Linux, `user://` is `~/.local/share/RuntimeTakeoff/`. On Windows it is `%APPDATA%\RuntimeTakeoff\`, and on macOS `~/Library/Application Support/RuntimeTakeoff/`.

Code: `scripts/telemetry/telemetry_core.gd`, which builds events and handles queueing, and `scripts/ui/main.gd`, which emits them.

## Envelope

| Field | Type | Notes |
|---|---|---|
| `schema` | int | Schema version, currently `1`. |
| `event` | string | Event name (see below). |
| `event_id` | uuid | Unique per event; use it for de-duplication on ingest. |
| `seq` | int | Increments within a session, starting at 1. Gaps mean lost events. |
| `ts` | string | UTC ISO-8601 with milliseconds, e.g. `2026-10-20T02:24:20.397Z`. |
| `ts_ms` | int | Unix epoch milliseconds. |
| `install_id` | uuid | Random per install. Reset or deleted from Settings. |
| `session_id` | uuid | Random per app launch. |
| `run_id` | uuid \| null | Random per run; null outside a run. |
| `seed` | int \| null | Run seed (reproduces the run); null outside a run. |
| `game_version` | string | `application/config/version`, e.g. `0.1.0`. |
| `build` | string | `debug` or `release`. |
| `platform` | string | `Windows`, `macOS`, or `Linux`. |
| `props` | object | Event-specific fields. |

## Upload

`POST <endpoint>` with `Content-Type: application/json` and the body `{"schema": 1, "events": [<envelope>, ...]}`. Batches hold up to 50 events and are sent every 30 seconds, or sooner when 50 are waiting.
The endpoint comes from the env var `AI_ERA_TELEMETRY_ENDPOINT`, or else the project setting `ai_era/telemetry/endpoint`. When neither is set, the no-op `NullSink` is used and events stay local.

| Response | Behavior | Log line (`user://logs/runtime-takeoff.log`) |
|---|---|---|
| 2xx | Batch removed from queue | none |
| no connection | Kept; backoff 30 s doubling up to 10 min | `WARN telemetry.send status=0 ...` |
| 5xx, 408, 429, 401, 403 | Retried with backoff; dropped after 5 attempts | `ERROR telemetry.send status=503 attempt=N ...` (the last line has `dropped=true`) |
| other 4xx | Dropped immediately | `ERROR telemetry.send status=400 ... dropped=true` |

The queue is capped at 5000 events, and the oldest are dropped first (`WARN telemetry.queue`). Find failures with `grep -E " ERROR " runtime-takeoff.log`.

## Events

| Event | When | `props` |
|---|---|---|
| `consent_changed` | Player opts in (first launch or Settings). Opting out records nothing and purges local data. | `granted` (true), `source` (`first_launch`\|`settings`) |
| `app_start` | Once per session, as soon as telemetry is on | `first_launch`, `locale`, `screen_w`, `screen_h`, `ui_scale`, `reduced_motion`, `fullscreen`, `steam`, and when on Steam: `steam_build_id`, `steam_deck`, `steam_language` |
| `app_exit` | Quit from the menu or window close | `source` (`title`\|`pause_menu`\|`window_close`\|`autoplay`), `session_ms` |
| `screen_view` | A screen or overlay opens | `screen` (`consent`\|`title`\|`game`\|`end`\|`pause`\|`settings`\|`privacy`) |
| `ui_interaction` | Any menu button or toggle | `element` (stable id, e.g. `title_new_run`, `pause_quit_title`), `action` (`press`\|`toggle`), `screen`, `input` |
| `settings_changed` | Any non-privacy setting changes | `key` (`ui/scale`\|`ui/reduced_motion`\|`display/fullscreen`), `old`, `new` |
| `install_id_reset` | Player resets the ID (logged under the new ID) | — |
| `run_start` | New run, replay, or custom seed | `seed_source` (`random`\|`custom`\|`replay`), `max_turns`, `start_date` |
| `decision` | Player picks a card or a dilemma response | `turn`, `date`, `kind` (`card`\|`dilemma`), `event_id` (dilemma only), `options_shown` (cards: `[{id, type, target}]`; dilemmas: `[{id, label}]`), `chosen_id`, `chosen_index`, `chosen_type` (cards), `decision_ms`, `input` (`keyboard`\|`mouse`\|`gamepad`\|`unknown`), `focus_changes`, `hover_changes` |
| `turn_resolved` | After each quarter resolves | `turn`, `date` `{year, quarter}`, `state` (world snapshot: `population_m`, `prosperity`, `jobs`, `unrest`, `compute`, `adoption`, `capability`, `safety`, `trust`, `inequality`), `events` (ids fired this quarter) |
| `overlay_changed` | Map overlay switched | `overlay`, `turn`, `input` |
| `pause` | Run paused | `reason` (`esc`\|`button`\|`focus_lost`), `turn` |
| `resume` | Run resumed | `pause_ms`, `turn` |
| `run_end` | Run reaches an ending | `ending`, `turns`, `final_date`, `population_start_m`, `population_end_m`, `state`, `levers`, `flags`, `picks_by_type`, `events_fired`, `richest_region`, `most_unrest_region`, `active_ms`, `pause_ms` |
| `run_abandon` | Run left before its ending | `reason` (`quit_to_title`\|`quit_game`\|`window_close`), `turn`, `date`, `active_ms`, `pause_ms`, `state` |

`decision_ms` and `active_ms` exclude time spent paused. `focus_changes` counts keyboard or mouse focus moves between options after the first. `hover_changes` counts mouse-overs.

## Rules for adding events

- Use only enumerated values, numbers, and ids. Never free text, names, SteamID, or paths.
- Additive changes keep `schema: 1`. Renaming or removing a field bumps `schema`.
- Add a test in `tests/test_telemetry.gd` for any new envelope field.
