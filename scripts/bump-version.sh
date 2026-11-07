#!/usr/bin/env bash
# Set the app version shown in About and the panel title (Config.xcconfig).
# Usage: scripts/bump-version.sh 0.1.5   -> edits Config.xcconfig; then commit, tag v0.1.5 and release.
set -euo pipefail
VERSION="${1:?usage: bump-version.sh <version>}"
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$' || { echo "invalid version: $VERSION" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
sed -i '' -E "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION/" "$ROOT/Config.xcconfig"
grep -n '^MARKETING_VERSION' "$ROOT/Config.xcconfig"
