#!/usr/bin/env bash
# Commit any new/changed plan files and push so GitHub Pages goes live within seconds.
# Run manually, or invoked by the LaunchAgent when a file lands in this folder.
# No-op if there is nothing to publish. Loop-safe and serialized.
set -euo pipefail

# launchd gives a bare PATH; pin Homebrew so git's `gh` credential helper is found.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# Serialize: if the watcher fires rapidly, only one publish runs at a time.
LOCK="/tmp/crossfit-plans-publish.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$(date '+%F %T') another publish in progress, skipping"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# Let a just-landed file finish writing before we commit it.
sleep 2

if [ -z "$(git status --porcelain)" ]; then
  echo "$(date '+%F %T') nothing to publish"
  exit 0
fi

git add -A
files="$(git diff --cached --name-only | tr '\n' ' ')"
git -c user.name="ragulshanmugam" -c user.email="ragulshanmugam3@gmail.com" \
  commit -m "Auto-publish: ${files}"
git push origin main
echo "$(date '+%F %T') published -> https://ragulshanmugam.github.io/crossfit-plans/"
