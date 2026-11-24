#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Local review archives do not use the Tuna Store signing key.
exec env -u SIGNING_KEY -u EXTENSIONS_STORE_SIGNING_PRIVATE_KEY_OP \
  "$repo_dir/TunaExtensions/scripts/ext-package.sh" HueExtension 'generic/platform=macOS'
