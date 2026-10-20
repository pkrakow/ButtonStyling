#!/usr/bin/env bash
# Runs the tests, then exports:
#   build/ios/       Xcode project (iPhone, unsigned) -> finish on a Mac, see docs/IOS_BUILD.md
#   build/linux/     desktop build for quick playtests
# Needs Godot 4.7.x as `godot` (or GODOT=/path/to/godot) with matching export templates.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd

rm -rf build
mkdir -p build/ios build/linux
"$GODOT" --headless --path . --export-release "iOS" build/ios/RuntimeTakeoff.ipa
"$GODOT" --headless --path . --export-release "Linux" build/linux/RuntimeTakeoff.x86_64

fail() { echo "ERROR export $1" >&2; exit 1; }
[[ -d build/ios/RuntimeTakeoff.xcodeproj ]] || fail "missing=build/ios/RuntimeTakeoff.xcodeproj"
[[ -s build/ios/RuntimeTakeoff.pck ]] || fail "missing=build/ios/RuntimeTakeoff.pck"
[[ -s build/linux/RuntimeTakeoff.x86_64 ]] || fail "missing=build/linux/RuntimeTakeoff.x86_64"
plist=build/ios/RuntimeTakeoff/RuntimeTakeoff-Info.plist
[[ $(grep -c "ITSAppUsesNonExemptEncryption" "$plist") == 1 ]] || fail "plist=$plist msg=\"ITSAppUsesNonExemptEncryption must appear exactly once\""
grep -A1 "ITSAppUsesNonExemptEncryption" "$plist" | grep -q "<false" || fail "plist=$plist msg=\"ITSAppUsesNonExemptEncryption must be false\""
grep -q 'TARGETED_DEVICE_FAMILY = "1"' build/ios/RuntimeTakeoff.xcodeproj/project.pbxproj || fail "msg=\"not iPhone-only\""
if strings build/ios/RuntimeTakeoff.pck | grep -q "steam_service.gd"; then fail "msg=\"Steam backend leaked into iOS pack\""; fi
echo "OK export ios=build/ios/RuntimeTakeoff.xcodeproj linux=build/linux/RuntimeTakeoff.x86_64"
