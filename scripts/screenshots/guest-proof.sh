#!/bin/bash
set -euo pipefail

cd "$HOME/tuna-hue-screenshot-run"
mode=${1:-}
appearance=${2:-}
case "$appearance" in
  light) appearance_label=Light ;;
  dark) appearance_label=Dark ;;
  *) exit 2 ;;
esac

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
socket="$HOME/Library/Application Support/Peekaboo/bridge.sock"
tuna=com.brnbw.Tuna
launcher_label="Connect First Hue Bridge"
step="check the guest tools and Tuna version"
trap 'printf "Guest screenshot failed while attempting to %s (line %s).\n" "$step" "$LINENO" >&2' ERR

tuna_plist=/Applications/Tuna.app/Contents/Info.plist
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$tuna_plist") == 0.113 ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$tuna_plist") == 2364 ]]
[[ $(peekaboo --version) =~ ^Peekaboo\ 4\.9\.9($|\ ) ]]
command -v jq >/dev/null

pb() {
  peekaboo "$@" --bridge-socket "$socket" --json
}

wait_for() {
  local deadline=$((SECONDS + 25))
  until "$@"; do
    if (( SECONDS >= deadline )); then
      printf 'Timed out while attempting to %s.\n' "$step" >&2
      if [[ -s ax.json ]]; then
        jq -c '{error, scope: .data.semantic_scope, labels: [.data.ui_elements[]? | [.label, .title, .value]]}' ax.json >&2
      fi
      return 1
    fi
    sleep 0.25
  done
}

observe() {
  pb see --window-id "$window" --fresh --tree --no-screenshot --timeout 5s >ax.json &&
    jq -e '.success and .data.semantic_scope == "exact_or_requested"' ax.json >/dev/null
}

bridge_ready() {
  pb permissions status >permissions.json && jq -e '.success' permissions.json >/dev/null
}

step="wait for Peekaboo Bridge at desktop login"
wait_for bridge_ready

step="check Peekaboo Bridge permissions and display"
jq -e '
  .data.source == "bridge" and
  ([.data.permissions[] | select(.isGranted) | .name] |
    index("Accessibility") != null and index("Screen Recording") != null)
' permissions.json >/dev/null || { cat permissions.json >&2; exit 1; }
pb screen list | jq -e '
  .success and (.data.screens | length == 1) and
  (.data.screens[0] | .bounds.width == 1600 and .bounds.height == 1000 and .scaleFactor == 2)
' >/dev/null

appearance_button() {
  settings_window=$(pb window list --app "System Settings" | jq -er '
    [.data.windows[] | select(.window_title == "Appearance" and .is_on_screen)]
    | select(length == 1) | .[0].window_id
  ') &&
    pb see --window-id "$settings_window" --fresh --tree --no-screenshot --timeout 5s >ax.json &&
    appearance_control=$(jq -er --arg label "$appearance_label" '
      select(.success and .data.semantic_scope == "exact_or_requested")
      | [.data.ui_elements[] | select(.label == $label and .ax_role == "AXButton"
          and (.help // "" | endswith("appearance for buttons, menus, and windows.")))]
      | select(length == 1) | .[0]
    ' ax.json)
}

appearance_selected() {
  local interface_style
  interface_style=$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)
  if [[ "$appearance" == dark ]]; then
    [[ "$interface_style" == Dark ]]
  else
    [[ -z "$interface_style" ]]
  fi
}

step="set macOS appearance to $appearance"
open 'x-apple.systempreferences:com.apple.Appearance-Settings.extension'
wait_for appearance_button
if ! jq -e '.is_selected == true' <<<"$appearance_control" >/dev/null; then
  pb click --window-id "$settings_window" --on "$(jq -er .id <<<"$appearance_control")" \
    --snapshot "$(jq -er .data.snapshot_id ax.json)" --foreground --input-strategy synthOnly \
    >appearance-click.json || true
  jq -e '.success or .outcome.mutation_dispatched' appearance-click.json >/dev/null ||
    { cat appearance-click.json >&2; exit 1; }
fi
wait_for appearance_selected
pkill -TERM -x 'System Settings' || true

step="install the developer extension and launch Tuna"
extensions="$HOME/Library/Application Support/Tuna/ExtensionsDev"
[[ ! -e "$extensions/TunaHue.framework" ]]
mkdir -p "$extensions"
ditto TunaHue.framework "$extensions/TunaHue.framework"
pkill -TERM -x Tuna || true
tuna_stopped() { ! pgrep -x Tuna >/dev/null; }
wait_for tuna_stopped
# Match the pinned Tuna Sources UI: All removes the override.
defaults export "$tuna" preferences.plist
if /usr/libexec/PlistBuddy -c "Print :CatalogScopes:hue.groups" preferences.plist >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Delete :CatalogScopes:hue.groups" preferences.plist
fi
defaults import "$tuna" preferences.plist
defaults write "$tuna" SearchCatalogGlobalDefaultsSeededCatalogs -array-add hue.groups
defaults write "$tuna" AutomaticallyShowResults -bool YES
defaults write "$tuna" ShowResultsImmediatelyOnActivation -bool YES

launch_args=(-g -j -F -n)
if [[ "$mode" == --all ]]; then
  step="start the mock Hue bridge"
  # Keep the server log readable by the guest user.
  # shellcheck disable=SC2024
  sudo -n ./bun mock-hue.ts >mock.log 2>&1 &
  mock_pid=$!
  trap 'sudo -n kill "$mock_pid" 2>/dev/null || true' EXIT
  mock_ready() {
    bridge_ca=$(sed -n 's/^CA PEM: //p' mock.log)
    [[ -n "$bridge_ca" ]] &&
      curl --fail --silent --cacert "$bridge_ca" https://127.0.0.1/__mock/discovery >/dev/null
  }
  wait_for mock_ready || { cat mock.log >&2; exit 1; }
  discovery=https://127.0.0.1/__mock/discovery
  launch_args+=(--env "TUNA_HUE_DISCOVERY_URL=$discovery" --env "TUNA_HUE_DISCOVERY_CA_PEM=$bridge_ca")
fi
step="launch Tuna after installing the extension"
tuna_running() {
  pgrep -x Tuna >/dev/null || { open "${launch_args[@]}" -a /Applications/Tuna.app >&2 || true; return 1; }
}
wait_for tuna_running
if [[ "$mode" == --all ]]; then
  step="verify Tuna received the mock discovery configuration"
  environment=$(ps eww -p "$(pgrep -x Tuna)" -o command=)
  [[ "$environment" == *"TUNA_HUE_DISCOVERY_URL=$discovery"* &&
     "$environment" == *"TUNA_HUE_DISCOVERY_CA_PEM=$bridge_ca"* ]]
  unset environment
fi
launcher_window() {
  window=$(./tuna-windows | jq -er '
    [.[] | select(.kCGWindowLayer == 3 and .kCGWindowBounds.Width == 792)]
    | select(length == 1) | .[0].kCGWindowNumber
  ') || return 1
}

step="verify the Hue command and expanded results"
last_search=-3
launcher_ready() {
  if launcher_window && observe &&
    jq -e --arg label "$launcher_label" 'any(.data.ui_elements[]; .label == $label)' ax.json >/dev/null; then
    if ./tuna-windows | jq -e --argjson id "$window" '
      any(.[]; .kCGWindowNumber == $id and .kCGWindowBounds.Height == 826)
    ' >/dev/null; then
      return 0
    fi
    if ! pb press down --app "$tuna" --foreground >key.json; then
      # Launcher's floating panel can be visible before the bridge can focus it.
      # The guest is dedicated to this run and the observed panel belongs to Tuna.
      pb press down --foreground --no-auto-focus >key-fallback.json || true
    fi
  elif (( SECONDS - last_search >= 3 )); then
    open 'tuna://search?q=hue'
    last_search=$SECONDS
  fi
  return 1
}
if ! wait_for launcher_ready; then
  ./tuna-windows >&2
  [[ ! -s key.json ]] || jq -c '{success, error, outcome}' key.json >&2
  [[ ! -s key-fallback.json ]] || jq -c '{success, error, outcome}' key-fallback.json >&2
  exit 1
fi

capture() {
  local number filename
  number=$(awk -v name="$1" '$0 == name { print NR; found=1 } END { exit !found }' order.txt)
  printf -v filename '%02d-%s-%s.png' "$number" "$1" "$appearance"
  printf 'Capturing %s\n' "$filename" >&2
  pb see --window-id "$window" --mode window --no-elements --retina --capture-engine cg \
    --timeout 10s --format png --path "$PWD/$filename" | jq -e '.success' >/dev/null
}
step="capture the exact Retina window"
capture find-hue-command
[[ "$mode" == --all ]] || exit 0

has_label() {
  jq -e --arg label "$1" '
    any(.data.ui_elements[]; .label == $label or .value == $label or .title == $label)
  ' ax.json >/dev/null
}

dialog() {
  local candidate
  for candidate in $(./tuna-windows | jq -r '.[] | select(.kCGWindowBounds.Width < 792) | .kCGWindowNumber'); do
    window=$candidate
    if observe && has_label "$1"; then return 0; fi
  done
  return 1
}

button_ready() {
  observe && button_id=$(jq -er --arg label "$1" '
    [.data.ui_elements[] | select(.label == $label and .ax_role == "AXButton"
      and .is_enabled == true)] | select(length == 1) | .[0].id
  ' ax.json) || return 1
}

button() {
  local snapshot attempt
  for attempt in 1 2; do
    wait_for button_ready "$1" || return 1
    snapshot=$(jq -er .data.snapshot_id ax.json)
    pb click --on "$button_id" --snapshot "$snapshot" --input-strategy actionOnly >click.json || true
    if jq -e '.success or .outcome.mutation_dispatched' click.json >/dev/null; then
      return 0
    fi
    printf 'Peekaboo could not press %s (attempt %s).\n' "$1" "$attempt" >&2
    cat click.json >&2
    jq -e '.outcome.retry_safe and (.outcome.mutation_dispatched == false)' click.json >/dev/null || return 1
  done
  return 1
}

press() {
  pb press "$1" --app "$tuna" --foreground >key.json || true
  if jq -e '.success or .outcome.mutation_dispatched' key.json >/dev/null; then
    return 0
  fi
  if jq -e '.outcome.retry_safe and (.outcome.mutation_dispatched == false)' key.json >/dev/null; then
    pb press "$1" --foreground --no-auto-focus >key.json || true
  fi
  jq -e '.success or .outcome.mutation_dispatched' key.json >/dev/null || { cat key.json >&2; return 1; }
}

picker_ready() {
  dialog "Select a Hue bridge to connect." &&
    jq -e 'any(.data.ui_elements[]; (.label // .value // "") | contains("Demo Hue Bridge"))' ax.json >/dev/null
}

step="capture the discovered bridge"
press return
wait_for picker_ready
capture choose-bridge

step="capture the blank manual connection form"
button 'Enter IP Address…'
wait_for dialog 'Connect Bridge'
capture manual-connection
button 'Connect automatically'

step="capture the link-button prompt"
wait_for picker_ready
button Continue
wait_for dialog 'Waiting for button press…'
capture press-link-button
curl --fail --silent --show-error --cacert "$bridge_ca" -X POST https://127.0.0.1/__mock/link-button

step="capture the pairing confirmation"
wait_for dialog 'Successfully connected to Hue bridge “Demo Hue Bridge”'
capture bridge-connected
button Done

search_ready() {
  launcher_window && observe && has_label "$1" && has_label "$2"
}

step="capture Bedroom with Turn On"
open 'tuna://search?q=Bedroom'
wait_for search_ready Bedroom 'Turn On'
capture turn-on

step="capture Living Room with Turn Off"
open 'tuna://search?q=Living%20Room'
wait_for search_ready 'Living Room' 'Turn Off'
press down
wait_for search_ready 'Living Room' 'Turn Off'
capture turn-off

step="capture offline Kitchen with Check Connection"
open 'tuna://search?q=Kitchen'
wait_for search_ready Kitchen 'Check Connection'
press down
wait_for search_ready Kitchen 'Check Connection'
capture check-connection

step="capture the Manage Hue Bridges dialog"
open 'tuna://search?q=Manage%20Hue%20Bridges'
wait_for search_ready 'Manage Hue Bridges' Run
press return
wait_for dialog 'Choose a connected bridge to disconnect.'
capture manage-bridges
button 'Disconnect…'

step="capture the disconnect confirmation"
wait_for dialog 'Disconnect “Demo Hue Bridge”?'
capture disconnect-bridge
