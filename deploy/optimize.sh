#!/bin/sh
# Builds dist/ from site/: the same files, plus precompressed copies of the scripts and styles.
# nginx serves dist/ while it matches site/ (deploy/prepare.sh checks), so serving is optional
# and a stale dist/ can never go live.
#
#   sh deploy/optimize.sh
#
# For each .js and .css file (and the manifest) it writes:
#   file.gz   system gzip -9
#   file.br   system Brotli, when available
# Every copy is decompressed again and compared with the original before it is kept. Pages, the
# worker, sitemap.xml and robots.txt are never precompressed: nginx fills in their SSI variables
# on every request, so a stored copy would be wrong.
#
set -eu
cd "$(dirname "$0")/.."
. deploy/tree-hash.sh

BROTLI=""
command -v brotli >/dev/null 2>&1 && BROTLI="brotli"
if [ -z "$BROTLI" ]; then echo "note: no brotli: writing .gz only" >&2; fi

rm -rf dist
mkdir dist
cp -R site/. dist/
rm -rf dist/_fx

raw=0; gz=0; br=0; files=0
compress_one() {
  f="$1"
  size=$(wc -c < "$f")
  [ "$size" -ge 256 ] || return 0

  gzip -9 -n -c "$f" > "$f.gz"
  if ! gzip -dc "$f.gz" | cmp -s - "$f"; then echo "gzip round trip failed: $f" >&2; exit 1; fi
  gsize=$(wc -c < "$f.gz")
  if [ "$gsize" -ge "$size" ]; then rm -f "$f.gz"; gsize=$size; fi

  bsize=$size
  if [ -n "$BROTLI" ]; then
    brotli -q 11 -c "$f" > "$f.br"
    if ! brotli -dc "$f.br" | cmp -s - "$f"; then echo "brotli round trip failed: $f" >&2; exit 1; fi
  fi
  if [ -f "$f.br" ]; then
    bsize=$(wc -c < "$f.br")
    if [ "$bsize" -ge "$gsize" ]; then rm -f "$f.br"; bsize=$gsize; fi
  fi
  raw=$((raw + size)); gz=$((gz + gsize)); br=$((br + bsize)); files=$((files + 1))
}

for f in $(find dist/assets -type f \( -name '*.js' -o -name '*.css' \) | LC_ALL=C sort) dist/manifest.webmanifest; do
  compress_one "$f"
done

tree_hash site > dist/.source-hash

pct() { echo $(( (100 * ($1 - $2)) / $1 )); }
echo "dist/ ready: $files files, $(tree_hash dist) (source $(cat dist/.source-hash))"
echo "  plain   $((raw / 1024)) KiB"
echo "  gzip -9 $((gz / 1024)) KiB (-$(pct "$raw" "$gz")%)"
if [ "$br" -lt "$gz" ]; then echo "  brotli  $((br / 1024)) KiB (-$(pct "$raw" "$br")%, $(pct "$gz" "$br")% under gzip)"; fi

echo
echo "Restart to serve it:  systemctl --user restart adimusic"
