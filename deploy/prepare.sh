#!/bin/sh
# Writes run/listen.conf from the environment (deploy/adimusic.env) and makes
# the runtime directories nginx needs. Run from the repo root.
set -eu
cd "$(dirname "$0")/.."
mkdir -p run/tmp/body run/tmp/proxy run/tmp/fastcgi run/tmp/uwsgi run/tmp/scgi run/cache

host="${ADI_HTTP_HOST:-127.0.0.1}"
port="${ADI_HTTP_PORT:-3000}"
key="${YOUTUBE_API_KEY:-}"

# The values land in an nginx config file: accept only plain characters.
case "$host" in ''|*[!0-9a-fA-F.:]*) echo "bad ADI_HTTP_HOST" >&2; exit 1;; esac
case "$port" in ''|*[!0-9]*) echo "bad ADI_HTTP_PORT" >&2; exit 1;; esac
case "$key" in *[!A-Za-z0-9_-]*) echo "ignoring YOUTUBE_API_KEY: unexpected characters" >&2; key="";; esac

# Where the site is served from: dist/ (made by deploy/optimize.sh) only while it matches site/.
# A stale dist/ must never be served, so a mismatch falls back to site/.
. deploy/tree-hash.sh
root=site
if [ -f dist/.source-hash ]; then
  if [ "$(tree_hash site)" = "$(cat dist/.source-hash)" ]; then
    root=dist
  else
    echo "dist/ is older than site/: serving site/ (run sh deploy/optimize.sh)" >&2
  fi
fi

# Content hash of what is served. It goes into every asset URL (?v=...), so browsers can cache
# them for a year and still pick up a change at once. ADI_DEV=1 turns caching off while editing.
if [ "${ADI_DEV:-0}" = "1" ]; then version="dev"; else version="$(tree_hash "$root")"; fi

# Canonical address for sitemap.xml, canonical links and social cards. Set it to the public
# https:// address in production; unset, it follows the request (fine for local use).
url="${ADI_PUBLIC_URL:-}"
url="${url%/}"
case "$url" in
  '') public_url='$scheme://$http_host' ;;
  http://*|https://*)
    case "$url" in *[!A-Za-z0-9.:/-]*) echo "bad ADI_PUBLIC_URL" >&2; exit 1;; esac
    public_url="$url" ;;
  *) echo "ADI_PUBLIC_URL must start with http:// or https://" >&2; exit 1 ;;
esac

{
  echo "listen $host:$port;"
  echo "root $root;"
  echo "set \$youtube_key \"$key\";"
  echo "set \$asset_v \"$version\";"
  echo "set \$public_url \"$public_url\";"
} > run/listen.conf
