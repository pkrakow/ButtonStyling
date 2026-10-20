# iOS build: export to TestFlight

The Xcode project is generated on Linux (or any OS). Signing, archiving, and uploading need a Mac with Xcode.

## What you need

| Item | Value |
|---|---|
| Godot | 4.7.2 stable, plus the matching export templates (Editor > Manage Export Templates, or unpack `Godot_v4.7.2-stable_export_templates.tpz` to `~/.local/share/godot/export_templates/4.7.2.stable/`) |
| Mac | macOS 15.6 or later |
| Xcode | 26.x from the Mac App Store. App Store Connect has required the iOS 26 SDK for uploads since April 2026. Check [Apple's upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) before each release. |
| Apple Developer Program | A paid membership, a team with the Admin or App Manager role, and your 10-character **Team ID** (developer.apple.com > Account > Membership details) |
| Minimum iOS | 15.0 |
| Devices | iPhone only (no iPad), portrait only |

## 1. Set the bundle ID and team (once)

The repo ships placeholders. Replace them in `export_presets.cfg`, section `[preset.3.options]`:

```ini
application/app_store_team_id="TEAMID1234"            ; your Team ID
application/bundle_identifier="com.example.runtimetakeoff" ; your reverse-DNS bundle ID
application/short_version="0.2.0"                      ; marketing version shown in the App Store
application/version="1"                                ; build number; bump for every upload
```

Do not commit a real Team ID if the repo is public. You can instead leave the placeholders and set the team in Xcode in step 3. Godot regenerates the Xcode project on every export, so you would need to set it again after each one.

Then register the bundle ID: in App Store Connect go to Apps > + > New App, pick Platform iOS, enter the name, the bundle ID (create it under Certificates, Identifiers & Profiles > Identifiers if it is not listed), and a SKU.

If you enable Game Center (optional, see below), use the same prefix in `ai_era/game_center/achievement_prefix` in `project.godot`.

## 2. Export the Xcode project (Linux or Mac)

```bash
cd games/ai-era
./tools/export_all.sh
```

This runs the tests, then exports `build/ios/` with `export_project_only=true`, so you get an unsigned Xcode project instead of an `.ipa`. It also checks the result and prints `OK export ios=build/ios/RuntimeTakeoff.xcodeproj ...`, or an `ERROR export ...` line saying what is wrong. To export iOS only:

```bash
mkdir -p build/ios
godot --headless --path . --export-release "iOS" build/ios/RuntimeTakeoff.ipa
```

Copy the whole `build/ios/` folder to the Mac. It contains `RuntimeTakeoff.xcodeproj`, the `RuntimeTakeoff/` sources and Info.plist, `RuntimeTakeoff.pck` (the game data), the engine `.xcframework`s, and `PrivacyInfo.xcprivacy`.

The preset already sets:

- **iPhone only:** `TARGETED_DEVICE_FAMILY = 1`, portrait orientation, full screen.
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO`, so App Store Connect does not ask the encryption question for each build. The game only uses HTTPS through the OS.
- **Privacy manifest:** no tracking, plus Product Interaction and Device ID for Analytics. It must match `docs/PRIVACY.md`. `tests/test_platform.gd` checks it against the telemetry ID scope.
- **No Steam code:** `scripts/platform/steam_service.gd` is excluded from the iOS pack.
- The 1024x1024 app icon from `assets/app_icon_1024.png`.

## 3. Sign in Xcode (Mac)

1. Open `build/ios/RuntimeTakeoff.xcodeproj` in Xcode.
2. Select the **RuntimeTakeoff** target > **Signing & Capabilities**.
3. Tick **Automatically manage signing**, pick your **Team**, and check that **Bundle Identifier** matches the App Store Connect app.
4. If you use Game Center, click **+ Capability** > **Game Center**.
5. To test, plug in an iPhone, select it as the run destination, and press **Run** (⌘R). Check portrait layout, safe areas around the Dynamic Island and home indicator, and that swiping home pauses the game. Reopen it and it should still be paused.

## 4. Archive and upload

1. Set the run destination to **Any iOS Device (arm64)**.
2. Choose **Product > Archive**. The Organizer opens when it finishes.
3. Select the archive > **Validate App** and fix anything it reports.
4. Choose **Distribute App** > **App Store Connect** > **Upload**. Keep automatic signing and the default options (upload symbols on, manage version and build number on).
5. Wait for the email "has completed processing", which usually takes 5–30 minutes.

Every upload needs a new build number. Bump `application/version` in the preset and export again, or let the Organizer increment it.

## 5. TestFlight

1. In App Store Connect > your app > **TestFlight**, the build shows up under iOS Builds. Because the compliance flag is set, it is ready right away.
2. **Internal testing** (up to 100 team members, no review): create an internal group, add testers, and add the build.
3. **External testing** (up to 10,000 people): create an external group and fill in Test Information (feedback email, beta description, privacy policy URL). Then add the build and submit it for Beta App Review. The first build of each version is reviewed.
4. Testers install the **TestFlight** app and accept the email or public link invitation.

Before App Store submission, also fill in **App Privacy** using the table at the end of `docs/PRIVACY.md`, host the privacy notice and enter its URL, set `ai_era/privacy_policy_url` in `project.godot` so the in-game button links to it, and upload iPhone screenshots. The dev capture flag makes portrait PNGs at any size (`--resolution 1206x2622 -- --capture=<dir>`). Check App Store Connect's current list of required screenshot sizes. The 6.9-inch set (1320x2868) is the one it asks for first, and 1206x2622 is the 6.3-inch size.

## Optional: Game Center

Game Center is off by default, and the game works without it. To turn it on:

1. Add the GameCenter plugin from [godot-ios-plugins](https://github.com/godot-sdk-integrations/godot-ios-plugins) built for Godot 4.7, and copy its `.gdip` and `.xcframework` into `ios/plugins/`.
2. Enable it in the iOS export preset (Plugins > GameCenter) and set `ai_era/game_center/enabled=true` in `project.godot`.
3. In App Store Connect > Game Center, create achievements whose IDs are `<achievement_prefix>.<api name in lowercase>`, e.g. `com.example.runtimetakeoff.ach_first_decision`. The full list is in `docs/STEAM.md` (shared rules in `scripts/platform/achievement_rules.gd`). Stats stay local because Game Center has no equivalent.
4. Add the Game Center capability in Xcode (step 3.4).

Without the plugin, the log shows `INFO platform.game_center mode=stub`, and achievements are only kept in memory.

## Troubleshooting

- `ERROR export missing=build/ios/RuntimeTakeoff.xcodeproj`: the iOS export templates are missing or don't match the Godot version. Run `godot --version` and check the templates folder.
- Xcode says "No account for team": add your Apple ID under Xcode > Settings > Accounts.
- Upload fails with "Invalid Bundle: duplicate key ITSAppUsesNonExemptEncryption": something added the key to `application/additional_plist_content`. Godot already writes it, so remove the extra one.
- Game logs on the device: Xcode > Window > Devices and Simulators > the app > Download Container, then open `AppData/Documents/logs/runtime-takeoff.log` and run `grep " ERROR "` on it.
