#!/bin/sh
# Regenerates site/assets/utilities.css from the UnoCSS runtime, using headless Chrome.
# Run it after adding or changing utility classes in HTML or JS:
#
#   sh tools/css-snapshot/snapshot.sh [base_url]     default: http://127.0.0.1:3030
#
# Needs Chrome or Chromium and python3. The site must be running (see the README).
set -eu
BASE="${1:-http://127.0.0.1:3030}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHROME="${CHROME:-$(command -v google-chrome || command -v google-chrome-stable || command -v chromium || command -v chromium-browser || true)}"
[ -n "$CHROME" ] || { echo "Chrome or Chromium not found. Set CHROME=/path/to/chrome." >&2; exit 1; }

mkdir -p "$ROOT/run"
"$CHROME" --headless=new --disable-gpu --no-sandbox --user-data-dir="$(mktemp -d)" \
  --virtual-time-budget=30000 --dump-dom "$BASE/?uno=snapshot" > "$ROOT/run/snapshot.html" 2>/dev/null
python3 "$HERE/extract.py" "$ROOT/run/snapshot.html" "$ROOT/site/assets/utilities.css"
