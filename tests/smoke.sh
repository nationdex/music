#!/bin/sh
# Smoke test for a running Adi Music instance (routes, SSI, headers, proxy allow-list).
#   sh tests/smoke.sh [base_url]      default: http://127.0.0.1:3000
set -u
BASE="${1:-http://127.0.0.1:3000}"
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "FAIL: $1"; }
code() { curl -s -o /dev/null -m 20 -w '%{http_code}' "$@"; }
want() { # want <status> <name> <curl args...>
  exp="$1"; name="$2"; shift 2
  got="$(code "$@")"
  [ "$got" = "$exp" ] && ok || bad "$name: expected $exp, got $got"
}

# pages and static files
for p in / /library /library/tracks /library/albums/abc /library/artists /library/playlists /discovery /settings /player \
         /components/home /components/tracks /components/collection /components/discovery /components/settings /components/player \
         /assets/app.css /assets/uno.config.js /assets/vendor/alpine.min.js /assets/vendor/alpine-persist.min.js \
         /assets/vendor/alpine-anchor.min.js /assets/vendor/alpine-focus.min.js /assets/vendor/alpine-intersect.min.js \
         /assets/vendor/unocss-runtime-core.js /assets/vendor/unocss-preset-wind4.js /assets/vendor/unocss-reset.css \
         /fonts/MPLUSRounded1c-Regular.woff2 /manifest.webmanifest /robots.txt /images/player.png /images/logo-64.png /assets/js/theme.js \
         /assets/js/app.js /assets/js/config.js /assets/js/palette.js /assets/js/tags.js /assets/js/db.js \
         /assets/js/util.js /assets/js/lyrics.js /assets/js/sources.js /assets/js/router.js; do
  want 200 "GET $p" "$BASE$p"
done

# SSI partials are expanded and not directly reachable
landing="$(curl -s -m 20 "$BASE/")"
echo "$landing" | grep -q 'system-icon-home' && ok || bad "landing: icon sprite not included (SSI)"
echo "$landing" | grep -q '<!--#' && bad "landing: unprocessed SSI directive" || ok
app="$(curl -s -m 20 "$BASE/library/tracks")"
echo "$app" | grep -q 'system-icon-fastForward' && ok || bad "app shell: icon sprite not included"
want 404 "partials are internal" "$BASE/partials/icons.html"
want 404 "unknown path" "$BASE/nope"
want 404 "/up/ index" "$BASE/up/"

# security headers
hdr="$(curl -sI -m 20 "$BASE/library/tracks")"
echo "$hdr" | grep -qi '^content-security-policy:.*frame-src https://www.youtube.com' && ok || bad "CSP missing frame-src youtube"
echo "$hdr" | grep -qi '^x-frame-options: DENY' && ok || bad "X-Frame-Options missing"
echo "$hdr" | grep -qi '^x-content-type-options: nosniff' && ok || bad "nosniff missing"
curl -sI -m 20 "$BASE/components/tracks" | grep -qi '^x-robots-tag: noindex' && ok || bad "components not noindex"

# the API key never reaches the browser
for p in / /library/tracks /assets/js/app.js /assets/js/sources.js /components/discovery; do
  curl -s -m 20 "$BASE$p" | grep -q 'AIza' && bad "API key leaked in $p" || ok
done

# proxy allow-list: only the exact endpoints, GET only
want 403 "POST blocked" -X POST "$BASE/up/itunes/search"
want 404 "other itunes endpoint" "$BASE/up/itunes/lookup?id=1"
want 404 "other adi endpoint" "$BASE/up/adi/api/health"
yt="$(code "$BASE/up/youtube/search?part=snippet&q=test&maxResults=1")"
case "$yt" in 200|503|403) ok;; *) bad "youtube search: unexpected $yt";; esac
want 200 "itunes search" "$BASE/up/itunes/search?term=daft+punk&media=music&entity=song&limit=1"

# UnoCSS runtime wiring: config, preset, core, in that order, on every page
for p in / /library/tracks; do
  html="$(curl -s -m 20 "$BASE$p")"
  a=$(printf '%s' "$html" | grep -bo 'uno.config.js' | head -1 | cut -d: -f1)
  b=$(printf '%s' "$html" | grep -bo 'unocss-preset-wind4.js' | head -1 | cut -d: -f1)
  c=$(printf '%s' "$html" | grep -bo 'unocss-runtime-core.js' | head -1 | cut -d: -f1)
  if [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]; then ok; else bad "$p: UnoCSS scripts missing or out of order"; fi
  printf '%s' "$html" | grep -q 'un-cloak' && ok || bad "$p: <html un-cloak> missing (flash of unstyled content)"
done

# Tailwind-only syntax that UnoCSS Wind4 does not generate (e.g. max-w-(--var)); use x-[var(--var)]
SITE="$(dirname "$0")/../site"
if grep -rnE '\b[a-z-]+-\(--[A-Za-z-]+\)' "$SITE"/*.html "$SITE"/components "$SITE"/partials 2>/dev/null | grep -q .; then
  bad "Tailwind paren shorthand x-(--var) found in site/: use x-[var(--var)]"
else ok; fi

# the client modules parse
if command -v node >/dev/null 2>&1; then
  for f in "$SITE"/assets/js/*.js; do
    node --input-type=module --check < "$f" 2>/dev/null && ok || bad "$(basename "$f") has a syntax error"
  done
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
