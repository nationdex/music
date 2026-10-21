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
         /assets/vendor/unocss-runtime-core.js /assets/vendor/unocss-preset-wind4.js \
         /fonts/MPLUSRounded1c-Regular.woff2 /manifest.webmanifest /robots.txt /images/player.png /images/logo-64.png /assets/js/theme.js \
         /assets/js/app.js /assets/js/config.js /assets/js/palette.js /assets/js/tags.js /assets/js/db.js \
         /assets/js/util.js /assets/js/eq.js /assets/js/zip.js /assets/js/presence.js /assets/js/lyrics.js /assets/js/sources.js /assets/js/router.js; do
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

# Innertube fallback proxy: POST only, small bodies only
want 403 "GET innertube blocked" "$BASE/up/innertube/search"
want 413 "oversized innertube body" -X POST -H 'Content-Type: application/json' --data "$(head -c 4000 /dev/zero | tr '\0' 'a')" "$BASE/up/innertube/search"
want 404 "other innertube endpoint" -X POST "$BASE/up/innertube/player"

# proxy allow-list: only the exact endpoints, GET only
want 403 "POST blocked" -X POST "$BASE/up/itunes/search"
want 404 "other itunes endpoint" "$BASE/up/itunes/lookup?id=1"
want 404 "other adi endpoint" "$BASE/up/adi/api/health"
yt="$(code "$BASE/up/youtube/search?part=snippet&q=test&maxResults=1")"
case "$yt" in 200|503|403) ok;; *) bad "youtube search: unexpected $yt";; esac
want 200 "itunes search" "$BASE/up/itunes/search?term=daft+punk&media=music&entity=song&limit=1"

# Stylesheets: the utilities snapshot comes before app.css (so app.css wins ties) and nothing waits
# on the UnoCSS runtime, which only loads on request (?uno=runtime)
for p in / /library/tracks /privacy; do
  html="$(curl -s -m 20 "$BASE$p")"
  u=$(printf '%s' "$html" | grep -bo 'assets/utilities.css' | head -1 | cut -d: -f1)
  c=$(printf '%s' "$html" | grep -bo 'assets/app.css' | head -1 | cut -d: -f1)
  if [ -n "$u" ] && [ -n "$c" ] && [ "$u" -lt "$c" ]; then ok; else bad "$p: utilities.css must be linked before app.css"; fi
  printf '%s' "$html" | grep -q 'assets/vendor/unocss-runtime-core.js' && bad "$p: the UnoCSS runtime must not load by default" || ok
done
want 200 "GET utilities.css" "$BASE/assets/utilities.css"
if [ "$(curl -s -m 20 "$BASE/assets/utilities.css" | grep -c '{')" -gt 300 ]; then ok; else bad "utilities.css looks empty: run sh tools/css-snapshot/snapshot.sh"; fi

# light-dark() fallback for Safari before 17.5 must match the tokens
python3 "$(dirname "$0")/../tools/css-compat/fallback.py" --check >/dev/null 2>&1 && ok || bad "app.css light-dark fallback is out of date: python3 tools/css-compat/fallback.py"

# SEO: canonical + social tags, valid structured data, sitemap, robots, noindex on the app
home="$(curl -s -m 20 "$BASE/")"
for tag in 'rel="canonical"' 'property="og:image"' 'name="twitter:card" content="summary_large_image"' 'name="description"' 'application/ld+json'; do
  printf '%s' "$home" | grep -q "$tag" && ok || bad "home page lacks $tag"
done
printf '%s' "$home" | python3 -c '
import sys, re, json
html = sys.stdin.read()
blocks = re.findall(r"<script type=\"application/ld\+json\">(.*?)</script>", html, re.S)
assert blocks, "no JSON-LD"
for b in blocks:
    d = json.loads(b)
    assert "@context" in d, "missing @context"
    if "@graph" in d:
        kinds = {n["@type"] for n in d["@graph"]}
        assert {"WebSite", "SoftwareApplication", "FAQPage"} <= kinds, kinds
        faq = [n for n in d["@graph"] if n["@type"] == "FAQPage"][0]
        assert len(faq["mainEntity"]) >= 3, "FAQ too short"
        assert len(re.findall("<summary", html)) == len(faq["mainEntity"]), "FAQ markup and JSON-LD disagree"
' 2>/dev/null && ok || bad "JSON-LD on the home page is invalid or does not match the visible FAQ"
curl -s -m 20 "$BASE/sitemap.xml" | python3 -c 'import sys,xml.dom.minidom as m; d=m.parseString(sys.stdin.read()); assert len(d.getElementsByTagName("loc"))>=2' 2>/dev/null && ok || bad "sitemap.xml is not valid XML with URLs"
curl -s -m 20 "$BASE/robots.txt" | grep -q '^Sitemap: http' && ok || bad "robots.txt lacks an absolute Sitemap line"
curl -s -m 20 "$BASE/robots.txt" | grep -q 'Disallow: /library/' && ok || bad "robots.txt must keep the player out"
curl -sI -m 20 "$BASE/library/tracks" | grep -qi '^x-robots-tag: noindex' && ok || bad "player routes must send X-Robots-Tag: noindex"
curl -s -m 20 "$BASE/library/tracks" | grep -q 'content="noindex, nofollow"' && ok || bad "player shell must carry meta robots noindex"
want 200 "GET /privacy" "$BASE/privacy"
want 301 "/privacy.html redirects" "$BASE/privacy.html"
want 404 "unknown path is a real 404" "$BASE/definitely-not-here"
curl -s -m 20 "$BASE/definitely-not-here" | grep -q 'Page not found' && ok || bad "404 page missing"
curl -sI -m 20 "$BASE/assets/app.css?v=abc123" | grep -qi 'cache-control: .*immutable' && ok || bad "versioned assets must be immutable"
curl -sI -m 20 "$BASE/assets/app.css" | grep -qi 'cache-control: no-cache' && ok || bad "unversioned assets must revalidate"

# Encodings: exactly one Content-Encoding, and the body decodes to the real file (br only when served)
plain_sum=$(curl -s -m 20 -H 'Accept-Encoding: identity' "$BASE/assets/js/app.js" | sha256sum | cut -d' ' -f1)
for enc in gzip br; do
  hdr="$(curl -s -o /dev/null -D - -m 20 -H "Accept-Encoding: $enc" "$BASE/assets/js/app.js")"
  n=$(printf '%s' "$hdr" | grep -ci '^content-encoding:')
  if [ "$n" -gt 1 ]; then bad "app.js sent $n Content-Encoding headers for $enc"; continue; fi
  if [ "$n" -eq 0 ]; then ok; continue; fi
  case "$enc" in
    gzip) got=$(curl -s -m 20 -H 'Accept-Encoding: gzip' "$BASE/assets/js/app.js" | gzip -dc | sha256sum | cut -d' ' -f1) ;;
    br) command -v brotli >/dev/null 2>&1 || { ok; continue; }
        got=$(curl -s -m 20 -H 'Accept-Encoding: br' "$BASE/assets/js/app.js" | brotli -dc | sha256sum | cut -d' ' -f1) ;;
  esac
  [ "$got" = "$plain_sum" ] && ok || bad "app.js $enc body does not decode to the original"
done

# The player's ES module graph is preloaded (no request waterfall)
python3 - "$(dirname "$0")/.." "$BASE" <<'PY' && ok || bad "app.html must modulepreload every module app.js imports"
import re, sys, urllib.request
root, base = sys.argv[1], sys.argv[2]
seen, queue = set(), ["app.js"]
while queue:
    f = queue.pop(0)
    for m in re.findall(r"from '\./([a-z-]+\.js)'", open("%s/site/assets/js/%s" % (root, f)).read()):
        if m not in seen and m != "app.js":
            seen.add(m); queue.append(m)
html = urllib.request.urlopen(base + "/library/tracks", timeout=20).read().decode()
preloaded = set(re.findall(r'rel="modulepreload" href="/assets/js/([a-z-]+\.js)"', html))
sys.exit(0 if seen <= preloaded else 1)
PY

# Tailwind-only syntax that UnoCSS Wind4 does not generate (e.g. max-w-(--var)); use x-[var(--var)]
SITE="$(dirname "$0")/../site"
if grep -rnE '\b[a-z-]+-\(--[A-Za-z-]+\)' "$SITE"/*.html "$SITE"/components "$SITE"/partials 2>/dev/null | grep -q .; then
  bad "Tailwind paren shorthand x-(--var) found in site/: use x-[var(--var)]"
else ok; fi

# PWA: worker, manifest, icons, and every file the worker precaches
SITE="$(dirname "$0")/../site"
hdr="$(curl -sI -m 20 "$BASE/sw.js")"
echo "$hdr" | grep -qi '^content-type: .*javascript' && ok || bad "sw.js is not served as JavaScript"
echo "$hdr" | grep -qi '^cache-control: no-cache' && ok || bad "sw.js must send Cache-Control: no-cache (restart nginx after config changes)"
curl -sI -m 20 "$BASE/manifest.webmanifest" | grep -qi '^content-type: application/manifest+json' && ok || bad "manifest content type"
for p in / /library/tracks; do
  html="$(curl -s -m 20 "$BASE$p")"
  printf '%s' "$html" | grep -q 'rel="manifest"' && ok || bad "$p: manifest link missing"
  printf '%s' "$html" | grep -q 'rel="apple-touch-icon"' && ok || bad "$p: apple-touch-icon missing"
  printf '%s' "$html" | grep -q 'apple-mobile-web-app-capable' && ok || bad "$p: iOS standalone meta missing"
done
if command -v jq >/dev/null 2>&1; then
  jq -e '.id and .name and .start_url and .scope and .display and (.icons | map(.purpose) | index("maskable"))' "$SITE/manifest.webmanifest" >/dev/null && ok || bad "manifest lacks id/name/start_url/scope/display or a maskable icon"
  for u in $(jq -r '[.icons[].src, .screenshots[].src, .shortcuts[].url, .file_handlers[].action] | .[]' "$SITE/manifest.webmanifest"); do
    want 200 "manifest asset $u" "$BASE$u"
  done
fi
for u in $(sed -n "/^const SHELL = \[/,/^\];/p" "$SITE/sw.js" | grep -o "'/[^']*'" | tr -d "'"); do
  want 200 "precache $u" "$BASE$u"
done

# the client modules parse
if command -v node >/dev/null 2>&1; then
  for f in "$SITE"/assets/js/*.js; do
    node --input-type=module --check < "$f" 2>/dev/null && ok || bad "$(basename "$f") has a syntax error"
  done
fi

# pure-logic tests (equalizer maths, ZIP reader); skipped when node is not installed
if command -v node >/dev/null 2>&1 && [ -d "$(dirname "$0")/js" ]; then
  node --test "$(dirname "$0")/js/" >/dev/null 2>&1 && ok || bad "node --test tests/js failed"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
