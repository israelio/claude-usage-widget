#!/usr/bin/env bash
# Point the Homebrew cask (israelio/homebrew-tap, Casks/claude-usage.rb) at a released version.
# Usage: scripts/update-cask.sh <version> <sha256-of-the-signed-dmg> [--dry-run]
# Called by scripts/release-signed.sh --upload; safe to re-run (no commit when already up to date).
set -euo pipefail

VERSION="${1:?usage: update-cask.sh <version> <sha256> [--dry-run]}"
SHA="${2:?usage: update-cask.sh <version> <sha256> [--dry-run]}"
DRY="${3:-}"
TAP_REPO="israelio/homebrew-tap"
CASK="Casks/claude-usage.rb"

echo "$SHA" | grep -Eq '^[0-9a-f]{64}$' || { echo "invalid sha256: $SHA" >&2; exit 1; }
TAPDIR="$(mktemp -d)"
trap 'rm -rf "$TAPDIR"' EXIT
git clone --quiet --depth 1 "https://github.com/$TAP_REPO.git" "$TAPDIR"

sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAPDIR/$CASK"
if git -C "$TAPDIR" diff --quiet; then
  echo "Homebrew cask already at $VERSION"; exit 0
fi
git -C "$TAPDIR" --no-pager diff --stat | tail -1
if [ "$DRY" = "--dry-run" ]; then echo "(dry run: not committing)"; exit 0; fi
git -C "$TAPDIR" commit -qam "claude-usage $VERSION"
git -C "$TAPDIR" push -q origin main
echo "Updated Homebrew cask to $VERSION"
