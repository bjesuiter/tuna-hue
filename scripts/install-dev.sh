#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
framework="${TUNA_EXTENSION_DERIVED_DATA:-$repo_dir/TunaExtensions/build/dd}/HueExtension/Build/Products/Release/TunaHue.framework"
dev_dir="$HOME/Library/Application Support/Tuna/ExtensionsDev"

if [[ ! -d "$framework" ]]; then
  printf 'TunaHue.framework is missing. Run bun run build:plugin first.\n' >&2
  exit 1
fi

mkdir -p "$dev_dir"
ditto "$framework" "$dev_dir/TunaHue.framework"

osascript <<'APPLESCRIPT'
if application id "com.brnbw.Tuna" is running then
  with timeout of 15 seconds
    tell application id "com.brnbw.Tuna" to quit
  end timeout
  repeat 50 times
    if not (application id "com.brnbw.Tuna" is running) then return
    delay 0.2
  end repeat
  error "Tuna did not quit. Quit it manually and reopen it to load the installed extension."
end if
APPLESCRIPT

open -b com.brnbw.Tuna
printf 'Installed TunaHue.framework and reopened Tuna.\n'
