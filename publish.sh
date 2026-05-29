#!/usr/bin/env bash
# Regenerate the all-plans listing, then commit any new/changed files and push so
# GitHub Pages goes live within seconds. Run manually or via the folder-watcher
# LaunchAgent. No-op if nothing changed. Loop-safe and serialized.
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

# Let a just-landed file finish writing before we touch it.
sleep 2

# --- Regenerate all.html: a browsable list of every plan, newest first. ---
# Deterministic output (no timestamps) so re-runs with no new plans are a no-op.
generate_listing() {
  local plans
  plans="$(ls -1 *.html 2>/dev/null | grep -vxE 'index\.html|all\.html' | sort -r || true)"
  {
    cat <<'HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CrossFit — All Plans</title>
<script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-slate-50 text-slate-900 antialiased">
  <div class="max-w-2xl mx-auto px-5 py-10">
    <p class="text-xs uppercase tracking-widest text-slate-500 font-semibold">CrossFit</p>
    <h1 class="mt-1 text-2xl font-extrabold">All Plans</h1>
    <p class="mt-1 mb-6 text-sm"><a href="./" class="text-rose-700 font-semibold hover:underline">&larr; Today's session</a></p>
    <ul class="divide-y divide-slate-200 rounded-2xl border border-slate-200 bg-white overflow-hidden">
HEAD
    if [ -z "$plans" ]; then
      echo '      <li class="px-5 py-4 text-slate-500">No plans yet.</li>'
    else
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        label="${f%.html}"
        printf '      <li><a class="block px-5 py-4 font-medium text-slate-800 hover:bg-slate-50" href="%s">%s</a></li>\n' "$f" "$label"
      done <<< "$plans"
    fi
    cat <<'FOOT'
    </ul>
  </div>
</body>
</html>
FOOT
  } > all.html
}

generate_listing

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
