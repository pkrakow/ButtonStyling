# Privacy notice

Draft for review. Before release, the publisher must fill in the bracketed items and host this notice at a public URL. App Store Connect requires that URL in the app's Privacy Policy field.

## Summary

Runtime: Takeoff can share **anonymous gameplay data** with its developers. Sharing is **off** unless you turn it on, either on the first-launch screen or in Settings. You can turn it off at any time. The game does not track you across other apps or websites, and it never asks for or reads your device's advertising identifier.

## What is collected when sharing is on

- **Gameplay events:** runs started, saved, resumed, and ended; each decision (the options you were shown, the one you picked, and how long you took); pauses; the app going to the background and coming back; map view changes; button presses and map taps; screens viewed; and settings changes.
- **Context:** game version, build type, operating system name, language code, and screen size.
- **Identifiers:** a random ID for each run. Depending on how this version of the game is configured, also a random install ID created on your device and a random ID for each session. Settings tells you which applies. None of these come from your Apple Account, Game Center, or hardware.

## What is never collected

Your Apple Account, Game Center ID, or any account details. The advertising identifier (IDFA) or the vendor identifier (IDFV). Your name, email, contacts, location, or photos. Anything you type. Seeds are numbers derived from what you enter, never the text itself. The game itself does not collect your IP address. [Publisher: confirm that the ingest server drops or truncates IP addresses.]

## Why

To learn which choices players find confusing, slow, or unbalanced, and to improve the game. The data is not used for advertising and is not sold or shared with data brokers. Legal basis: your consent (GDPR Art. 6(1)(a), ePrivacy Art. 5(3)).

## Where it goes

Events are written to a file on your device, then uploaded in batches to [Publisher: analytics provider and region]. If you are offline, they wait in a local queue and upload later. Batches the server keeps rejecting are deleted after five attempts.

## How long it is kept

[Publisher: retention period, 12 months or less.]

## Your choices and rights

- **Turn sharing off:** go to Settings and switch off "Share anonymous play data". This stops recording and deletes all play data stored on this device that has not been uploaded.
- **Reset your ID:** when the game uses an install ID, Settings shows it with a "Reset ID" button. Resetting creates a new random ID and deletes data stored on this device under the old one.
- **Access or delete uploaded data:** email [Publisher: contact email] with the install ID shown in Settings. You can also object or complain to your data protection authority.
- **Delete everything:** deleting the app removes all of its data from your device.

## Local files

These stay on your device and are never uploaded: settings, your saved run, the list of endings you have found, the local event log, and an error log. The error log records technical failures only, such as an upload that failed.

## Game Center

If this version uses Game Center, achievements are handled by Apple under Apple's privacy policy. The game only tells Game Center which achievements you earned.

## Contact

Data controller: [Publisher: legal name and address]. Email: [Publisher: contact email].

## App Store privacy label (publisher reference)

This section is for filling in App Privacy in App Store Connect and is not shown in the game. Opt-in data must still be declared. Apple's "optional disclosure" exception does not apply, because collection is ongoing once a player opts in.

Answer "Yes, we collect data from this app", then declare the following based on `ai_era/telemetry/id_scope` in `project.godot`. Changing the switch means changing the label, the iOS preset's privacy manifest options (`tests/test_platform.gd` checks they match), and this notice.

| App Store category | `id_scope = "install"` (current default) | `id_scope = "run"` |
|---|---|---|
| Usage Data > Product Interaction | Collected. Purpose: Analytics. Linked to the user: **Yes**, through the persistent install ID. Tracking: No. | Collected. Purpose: Analytics. Linked to the user: **No**. Tracking: No. |
| Identifiers > Device ID | Collected (the random install ID is a device-level ID). Purpose: Analytics. Linked: Yes. Tracking: No. | Not collected. |
| Identifiers > User ID | Not collected. | Not collected. |
| Diagnostics (Crash Data, Performance Data) | Not collected. The error log stays on the device. | Not collected. |
| Diagnostics > Other Diagnostic Data | Not declared. The context fields (version, OS, language, screen size) describe the gameplay events and are covered by Product Interaction. Declare this too if App Review asks. | Same. |
| Everything else (contact info, location, purchases, contacts, user content, search and browsing history, sensitive info, health, financial info) | Not collected. | Not collected. |

Other App Store Connect answers:

- **Tracking:** No. The game uses no IDFA, no ad SDKs, and no data brokers, so it does not need the App Tracking Transparency prompt. The privacy manifest sets `NSPrivacyTracking` to false.
- **Third-party SDKs:** none in the default build. If you add an analytics provider or the Game Center plugin, check their privacy manifests and update this table.
- **Age rating questionnaire:** no user-generated content, no unrestricted web access, and no gambling. The optional privacy policy button opens a single URL in Safari.
