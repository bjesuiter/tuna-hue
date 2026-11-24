#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_dir/packages/website/src/assets/screenshots"
extension_repo="$repo_dir/TunaExtensions"
destination="$extension_repo/media/screenshots/tuna-hue"

if [[ ! -e "$extension_repo/.git" || ! -d "$extension_repo/HueExtension" ]]; then
  echo "Check out the TunaExtensions submodule with HueExtension before syncing screenshots." >&2
  exit 1
fi

shopt -s nullglob
screenshots=("$source_dir/"*.png)
if (( ${#screenshots[@]} == 0 )); then
  echo "No website screenshots found in $source_dir." >&2
  exit 1
fi

mkdir -p "$destination"
rsync -r --checksum --delete --include='/*.png' --exclude='*' "$source_dir/" "$destination/"
printf 'Synced %s screenshots to TunaExtensions/media/screenshots/tuna-hue\n' "${#screenshots[@]}"
