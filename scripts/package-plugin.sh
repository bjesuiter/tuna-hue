#!/bin/bash
set -euo pipefail

: "${TUNA_DEVELOPMENT_TEAM:?Set TUNA_DEVELOPMENT_TEAM to your Apple Development team ID.}"
: "${TUNA_CODE_SIGN_IDENTITY:?Set TUNA_CODE_SIGN_IDENTITY to the SHA-1 from security find-identity -v -p codesigning.}"

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_dir/build/package-plugin"
packager_revision=1d26b3186812a4b731ec6389eecd31b2a4614023
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

curl -fsSL --retry 3 "https://codeload.github.com/tunaformac/TunaExtensions/tar.gz/$packager_revision" \
  -o "$staging_dir/upstream.tar.gz"
tar -xzf "$staging_dir/upstream.tar.gz" -C "$staging_dir" --strip-components 1 \
  "TunaExtensions-$packager_revision/scripts"
rsync -a --exclude=/build/ --exclude=xcuserdata "$repo_dir/packages/plugin/" "$staging_dir/HueExtension/"

# This is a local review package. Tuna applies the store signature during publication.
env -u SIGNING_KEY -u EXTENSIONS_STORE_SIGNING_PRIVATE_KEY_OP \
  TUNA_XCODEBUILD_LOG_DIR="$output_dir/xcodebuild" \
  "$staging_dir/scripts/ext-package.sh" TunaHue 'generic/platform=macOS'

shopt -s nullglob
packages=("$staging_dir"/dist/store/*.tunaextension)
if [[ ${#packages[@]} -ne 1 ]]; then
  printf 'Expected one .tunaextension package, found %s.\n' "${#packages[@]}" >&2
  exit 1
fi

unzip -tq "${packages[0]}"
mkdir -p "$output_dir"
cp "${packages[0]}" "$output_dir/"
printf 'Review package: %s/%s\n' "$output_dir" "${packages[0]##*/}"
