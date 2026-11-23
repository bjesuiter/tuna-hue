#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."
tart=${TART_BIN:-tart}
image=${TUNA_HUE_SCREENSHOT_VM:-tuna-hue-screenshots-v1}
guest_user=${TUNA_HUE_SCREENSHOT_USER:-admin}
state_dir="$HOME/.local/state/tuna-hue-screenshots"
host_keys=${TUNA_HUE_SCREENSHOT_HOST_KEYS:-$state_dir/known_hosts}
identity=${TUNA_HUE_SCREENSHOT_SSH_KEY:-}
if [[ -z "$identity" && -f "$state_dir/id_ed25519" ]]; then
  identity="$state_dir/id_ed25519"
fi
clone="tuna-hue-shot-$(uuidgen | tr '[:upper:]' '[:lower:]')"
staging=
publish_stage=
vm_pid=
clone_requested=false
step="check host prerequisites"
mode=${1:-}
[[ -z "$mode" || "$mode" == --all || "$mode" == --publish ]] || exit 2

clean_clone() {
  if [[ -n "$vm_pid" ]]; then
    "$tart" stop "$clone" >/dev/null 2>&1 || kill "$vm_pid" 2>/dev/null || true
    wait "$vm_pid" 2>/dev/null || true
    vm_pid=
  fi
  if "$clone_requested" && "$tart" get "$clone" >/dev/null 2>&1; then
    "$tart" delete "$clone" || return 1
  fi
  clone_requested=false
}

cleanup() {
  local status=$?
  trap - EXIT
  if (( status != 0 )); then
    printf 'Screenshot failed while attempting to %s (exit %s).\n' "$step" "$status" >&2
    if [[ -n "$staging" && -f "$staging/tart.log" ]]; then
      tail -n 15 "$staging/tart.log" >&2
    fi
  fi
  if ! clean_clone; then
    printf 'Could not delete run clone %s.\n' "$clone" >&2
    status=1
  fi
  if [[ -n "$staging" ]]; then
    if (( status == 0 )) && [[ "$mode" != --publish ]]; then
      printf 'Staged PNGs: %s\n' "$staging"
    else
      rm -rf -- "$staging"
    fi
  fi
  if [[ -n "$publish_stage" ]]; then rm -rf -- "$publish_stage"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ $(uname -sm) == "Darwin arm64" ]] || { echo "An Apple Silicon Mac is required." >&2; exit 1; }
command -v "$tart" >/dev/null
command -v bun >/dev/null
[[ "$image" != */* || "$image" =~ @sha256:[[:xdigit:]]{64}$ ]] ||
  { echo "Remote VM references must include an OCI SHA-256 digest." >&2; exit 1; }

step="clone the prepared VM $image"
export TART_NO_AUTO_PRUNE=1
if "$tart" get "$clone" >/dev/null 2>&1; then
  echo "The generated clone name already exists. Retry to allocate a fresh name." >&2
  exit 1
fi
clone_requested=true
"$tart" clone "$image" "$clone"

step="check the prepared VM's SSH host key"
ssh-keygen -F tuna-hue-screenshots -f "$host_keys" >/dev/null

step="build TunaHue.framework"
bun run build:plugin
framework=packages/plugin/build/Build/Products/Release/TunaHue.framework
[[ -f "$framework/TunaHue" ]]
staging=$(mktemp -d "${TMPDIR:-/tmp}/tuna-hue-proof.XXXXXXXX")
xcrun swiftc -target arm64-apple-macos15 scripts/screenshots/tuna-windows.swift -o "$staging/tuna-windows"

step="boot and locate the VM clone"
"$tart" run --no-graphics --no-audio --no-clipboard "$clone" >"$staging/tart.log" 2>&1 &
vm_pid=$!
ip=$("$tart" ip --wait 120 "$clone")

ssh_guest() {
  local options=()
  if [[ -n "$identity" ]]; then
    options=(-o IdentitiesOnly=yes -i "$identity")
  fi
  /usr/bin/perl -e 'alarm shift; exec @ARGV or die $!' "${SSH_LIMIT:-90}" ssh \
    -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
    -o StrictHostKeyChecking=yes -o HostKeyAlias=tuna-hue-screenshots \
    -o "UserKnownHostsFile=\"$host_keys\"" ${options[@]+"${options[@]}"} -- "$guest_user@$ip" "$@"
}

step="wait for SSH and the guest's desktop login"
deadline=$((SECONDS + 90))
# The console user and UID must be read in the guest.
# shellcheck disable=SC2016
until ssh_guest 'test "$(stat -f %Su /dev/console)" = "$(id -un)" && launchctl print gui/$(id -u) >/dev/null'; do
  (( SECONDS < deadline ))
  sleep 1
done

step="copy the new framework and capture script"
cp scripts/screenshots/guest-proof.sh "$staging/guest-proof.sh"
payload=(guest-proof.sh tuna-windows)
if [[ -n "$mode" ]]; then
  cp -L "$(command -v bun)" "$staging/bun"
  cp packages/hue-mock/server.ts "$staging/mock-hue.ts"
  payload+=(bun mock-hue.ts)
fi
COPYFILE_DISABLE=1 tar -czf - -C "$(dirname "$framework")" "$(basename "$framework")" \
  -C "$staging" "${payload[@]}" | ssh_guest 'mkdir -p ~/tuna-hue-screenshot-run && tar -xzf - -C ~/tuna-hue-screenshot-run'

step="capture the launcher proof in the guest"
if [[ -n "$mode" ]]; then
  SSH_LIMIT=300 ssh_guest '/bin/bash ~/tuna-hue-screenshot-run/guest-proof.sh --all'
  ssh_guest 'cd ~/tuna-hue-screenshot-run && tar -czf - *.png' | tar -xzf - -C "$staging"
  sips -g pixelWidth -g pixelHeight "$staging/"*.png
else
  ssh_guest 'cat ~/tuna-hue-screenshot-run/find-hue-command.png' >"$staging/find-hue-command.png"
fi

step="validate the proof PNG"
png_info=$(sips -g format -g pixelWidth -g pixelHeight "$staging/find-hue-command.png")
printf '%s\n' "$png_info"
[[ "$png_info" == *"format: png"* && "$png_info" == *"pixelWidth: 1584"$'\n'* &&
  "$png_info" == *"pixelHeight: 1652" ]] ||
  { echo "Expected the expanded launcher window at 1584 × 1652 pixels." >&2; exit 1; }

for item in "${payload[@]}" tart.log; do rm "$staging/$item"; done

if [[ "$mode" == --publish ]]; then
  step="remove the screenshot VM clone"
  clean_clone
  step="validate and replace the website PNGs"
  destination=packages/website/src/assets/screenshots
  publish_stage=$(mktemp -d "${destination%/*}/.screenshots.XXXXXXXX")
  chmod "$(/usr/bin/stat -f '%Lp' "$destination")" "$publish_stage"
  cp "$staging/"*.png "$publish_stage/"
  xcrun swift scripts/screenshots/publish.swift "$publish_stage" "$destination"
  printf 'Replaced all website PNGs in %s\n' "$destination"
fi
