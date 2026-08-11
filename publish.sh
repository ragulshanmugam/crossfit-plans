#!/usr/bin/env bash
# Regenerate the all-plans browse page, then commit any new/changed files and push
# so GitHub Pages goes live within seconds. Run manually or via the folder-watcher
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

# --- Reap stale git locks -------------------------------------------------
# Claude's sandbox mounts this folder without delete permission. Git creates
# .git/index.lock, .git/HEAD.lock and .git/objects/*/tmp_obj_* during writes and
# removes them with unlink() on cleanup paths -- which silently fails there,
# leaving the repo permanently locked. Any lock older than 5 minutes cannot
# belong to a live git process (this script is serialized by $LOCK), so reap it.
reap_stale_locks() {
  local stale
  stale="$(find .git -maxdepth 3 \
    \( -name '*.lock' -o -name 'tmp_obj_*' \) -mmin +5 -print 2>/dev/null || true)"
  if [ -n "$stale" ]; then
    echo "$(date '+%F %T') reaping stale git locks:"
    echo "$stale" | sed 's/^/  /'
    echo "$stale" | while IFS= read -r f; do rm -f "$f" 2>/dev/null || true; done
  fi
}
reap_stale_locks

# Strip HTML tags, quotes, angle brackets and collapse whitespace for safe embedding.
sanitize() { printf '%s' "$1" | sed 's/<[^>]*>//g' | tr -d '"\\<>' | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//'; }

# --- Regenerate all.html: calendar + searchable cards. Deterministic (no timestamps). ---
generate_listing() {
  local plans f date weekday title focus rows=""
  plans="$(ls -1 *.html 2>/dev/null | grep -vxE 'index\.html|all\.html' | sort -r || true)"
  if [ -n "$plans" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if [[ "$f" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-([A-Za-z]+)\.html$ ]]; then
        date="${BASH_REMATCH[1]}"; weekday="${BASH_REMATCH[2]}"
      else
        date=""; weekday=""
      fi
      title="$(sanitize "$(sed -n 's:.*<title>\(.*\)</title>.*:\1:p' "$f" | head -1)")"
      focus="$(sanitize "$(grep -i 'Focus:' "$f" | head -1 | sed 's/.*Focus:[[:space:]]*//')")"
      rows+="    {\"file\":\"$f\",\"date\":\"$date\",\"weekday\":\"$weekday\",\"title\":\"$title\",\"focus\":\"$focus\"},"$'\n'
    done <<< "$plans"
  fi

  {
    cat <<HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CrossFit — All Plans</title>
<script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-slate-50 text-slate-900 antialiased">
  <div class="max-w-xl mx-auto px-4 py-8">
    <p class="text-xs uppercase tracking-widest text-slate-500 font-semibold">CrossFit</p>
    <h1 class="mt-1 text-2xl font-extrabold mb-1">All Plans</h1>
    <p class="mb-5 text-sm"><a href="./" class="text-rose-700 font-semibold hover:underline">&larr; Today's session</a></p>
    <div class="flex gap-2 mb-5">
      <button id="tabCal" type="button">Calendar</button>
      <button id="tabList" type="button">List</button>
    </div>
    <section id="calView">
      <div class="flex items-center justify-between mb-3">
        <button id="prevBtn" type="button" class="px-3 py-1 rounded-lg border border-slate-300 hover:bg-slate-100">&larr;</button>
        <div id="monthLabel" class="font-bold"></div>
        <button id="nextBtn" type="button" class="px-3 py-1 rounded-lg border border-slate-300 hover:bg-slate-100">&rarr;</button>
      </div>
      <div id="grid" class="grid grid-cols-7 gap-1"></div>
    </section>
    <section id="listView" class="hidden">
      <input id="search" type="search" placeholder="Search by date, weekday, focus…" class="w-full mb-4 px-4 py-2 rounded-xl border border-slate-300 focus:outline-none focus:ring-2 focus:ring-rose-300">
      <div id="cards" class="space-y-3"></div>
    </section>
  </div>
  <script>
  const PLANS = [
$rows
  ];
HEAD
    cat <<'JS'
  (function () {
    var byDate = {};
    PLANS.forEach(function (p) { if (p.date) { byDate[p.date] = p; } });
    var MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"];
    var DOW = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];

    var cur;
    if (PLANS.length && PLANS[0].date) { var s = PLANS[0].date.split("-"); cur = new Date(+s[0], +s[1] - 1, 1); }
    else { var n = new Date(); cur = new Date(n.getFullYear(), n.getMonth(), 1); }

    function pad(n) { return String(n).padStart(2, "0"); }
    function ymd(y, m, d) { return y + "-" + pad(m + 1) + "-" + pad(d); }
    function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

    function fmt(p) {
      if (p.date) { var s = p.date.split("-"); var dt = new Date(+s[0], +s[1] - 1, +s[2]); return (p.weekday || DOW[dt.getDay()]) + ", " + MONTHS[dt.getMonth()] + " " + dt.getDate() + ", " + dt.getFullYear(); }
      return p.file.replace(/\.html$/, "");
    }

    function renderCal() {
      var y = cur.getFullYear(), m = cur.getMonth();
      document.getElementById("monthLabel").textContent = MONTHS[m] + " " + y;
      var first = new Date(y, m, 1).getDay();
      var days = new Date(y, m + 1, 0).getDate();
      var today = new Date(), todayStr = ymd(today.getFullYear(), today.getMonth(), today.getDate());
      var grid = document.getElementById("grid");
      grid.replaceChildren();
      DOW.forEach(function (d) { grid.appendChild(el("div", "text-center text-xs font-semibold text-slate-400 py-1", d)); });
      for (var i = 0; i < first; i++) { grid.appendChild(el("div")); }
      for (var d = 1; d <= days; d++) {
        var key = ymd(y, m, d), p = byDate[key];
        var ring = key === todayStr ? " ring-2 ring-rose-400" : "";
        if (p) {
          var a = el("a", "flex items-center justify-center aspect-square rounded-xl bg-rose-600 text-white font-bold hover:bg-rose-700" + ring, String(d));
          a.href = p.file; a.title = p.focus || p.title || "";
          grid.appendChild(a);
        } else {
          grid.appendChild(el("div", "flex items-center justify-center aspect-square rounded-xl text-slate-400" + ring, String(d)));
        }
      }
    }

    function renderCards(filter) {
      filter = (filter || "").toLowerCase();
      var cont = document.getElementById("cards");
      cont.replaceChildren();
      var shown = 0;
      PLANS.forEach(function (p) {
        var sub = p.focus || p.title || "";
        if (filter && (p.file + " " + fmt(p) + " " + sub).toLowerCase().indexOf(filter) < 0) return;
        var a = el("a", "block rounded-2xl border border-slate-200 bg-white px-5 py-4 hover:border-rose-300 hover:shadow-sm");
        a.href = p.file;
        a.appendChild(el("div", "font-bold text-slate-900", fmt(p)));
        if (sub) a.appendChild(el("div", "mt-1 text-sm text-slate-600", sub));
        cont.appendChild(a);
        shown++;
      });
      if (!shown) cont.appendChild(el("p", "text-slate-500 px-1", "No matches."));
    }

    function setActive(id, on) {
      document.getElementById(id).className = "px-4 py-2 rounded-xl text-sm font-semibold " + (on ? "bg-slate-900 text-white" : "bg-white text-slate-700 border border-slate-300");
    }
    function show(view) {
      var cal = view === "cal";
      document.getElementById("calView").classList.toggle("hidden", !cal);
      document.getElementById("listView").classList.toggle("hidden", cal);
      setActive("tabCal", cal); setActive("tabList", !cal);
    }

    document.getElementById("prevBtn").onclick = function () { cur = new Date(cur.getFullYear(), cur.getMonth() - 1, 1); renderCal(); };
    document.getElementById("nextBtn").onclick = function () { cur = new Date(cur.getFullYear(), cur.getMonth() + 1, 1); renderCal(); };
    document.getElementById("tabCal").onclick = function () { show("cal"); };
    document.getElementById("tabList").onclick = function () { show("list"); };
    document.getElementById("search").addEventListener("input", function (e) { renderCards(e.target.value); });

    renderCal(); renderCards(""); show("cal");
  })();
  </script>
</body>
</html>
JS
  } > all.html
}

generate_listing

if [ -z "$(git status --porcelain)" ]; then
  echo "$(date '+%F %T') nothing to publish"
  exit 0
fi

# --- Commit & push, retrying once through a fresh lock reap ---------------
# `set -e` used to abort the script here the moment a stale lock existed, and
# under launchd that exit code went nowhere -- days of workouts piled up with no
# error. Now a failure reaps locks (ignoring age) and retries, then shouts.
publish_attempt() {
  git add -A || return 1
  local files
  files="$(git diff --cached --name-only | tr '\n' ' ')"
  # Another process may have committed between our add and here; that's fine.
  if [ -n "$(git diff --cached --name-only)" ]; then
    git -c user.name="ragulshanmugam" -c user.email="ragulshanmugam3@gmail.com" \
      commit -m "Auto-publish: ${files}" || return 1
  fi
  # Push whatever is unpushed, including commits made by earlier failed runs.
  git push origin main || return 1
  return 0
}

if publish_attempt; then
  echo "$(date '+%F %T') published -> https://ragulshanmugam.github.io/crossfit-plans/"
else
  echo "$(date '+%F %T') publish failed -- reaping all locks and retrying once" >&2
  find .git -maxdepth 3 \( -name '*.lock' -o -name 'tmp_obj_*' \) -delete 2>/dev/null || true
  if publish_attempt; then
    echo "$(date '+%F %T') published on retry -> https://ragulshanmugam.github.io/crossfit-plans/"
  else
    echo "$(date '+%F %T') PUBLISH STILL FAILING -- manual attention needed" >&2
    # Make the failure impossible to miss: desktop notification + unpushed count.
    ahead="$(git rev-list --count @{u}..HEAD 2>/dev/null || echo '?')"
    /usr/bin/osascript -e "display notification \"crossfit-plans publish failed. ${ahead} commit(s) unpushed.\" with title \"Publish failed\"" 2>/dev/null || true
    exit 1
  fi
fi
