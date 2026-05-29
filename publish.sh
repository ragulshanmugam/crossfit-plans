#!/usr/bin/env bash
# Commit any new/changed plan files and push so GitHub Pages goes live within seconds.
# Safe to run from anywhere; no-op if there is nothing to publish.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

if [ -z "$(git status --porcelain)" ]; then
  echo "Nothing to publish."
  exit 0
fi

git add -A
git -c user.name="ragulshanmugam" -c user.email="ragulshanmugam3@gmail.com" \
  commit -m "Publish plan update $(git status --porcelain | awk '{print $2}' | tr '\n' ' ')"
git push origin main
echo "Published. Live shortly at https://ragulshanmugam.github.io/crossfit-plans/"
