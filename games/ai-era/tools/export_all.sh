#!/usr/bin/env bash
# Runs the tests, then exports Windows, Linux and macOS release builds into build/.
# Needs Godot 4.7.x on PATH as `godot` (or set GODOT=/path/to/godot) and matching
# export templates installed. macOS output is unsigned; see docs/STEAM.md.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd

rm -rf build
mkdir -p build/windows build/linux build/macos
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/RuntimeTakeoff.exe
"$GODOT" --headless --path . --export-release "Linux" build/linux/RuntimeTakeoff.x86_64
"$GODOT" --headless --path . --export-release "macOS" build/macos/RuntimeTakeoff.zip

for f in build/windows/RuntimeTakeoff.exe build/linux/RuntimeTakeoff.x86_64 build/macos/RuntimeTakeoff.zip; do
  if [[ ! -s "$f" ]]; then
    echo "ERROR export missing=$f" >&2
    exit 1
  fi
  echo "OK export file=$f bytes=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f")"
done
