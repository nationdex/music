#!/bin/sh
# Builds dist/ from site/: the same files, plus precompressed copies of the scripts and styles.
# nginx serves dist/ while it matches site/ (deploy/prepare.sh checks), so serving is optional
# and a stale dist/ can never go live.
#
#   sh deploy/optimize.sh
#
# For each .js and .css file (and the manifest) it writes:
#   file.gz   gzip -9 (the system gzip beats nstd's gzip by about 7%)
#   file.br   Brotli level 9 from nationdex/nstd (bin/nstd), or the system `brotli` as a fallback
# Every copy is decompressed again and compared with the original before it is kept. Pages, the
# worker, sitemap.xml and robots.txt are never precompressed: nginx fills in their SSI variables
# on every request, so a stored copy would be wrong.
#
# With bin/astroisle (nationdex/astroisle) it also audits the size budgets.
set -eu
cd "$(dirname "$0")/.."
. deploy/tree-hash.sh

NSTD=""
[ -x bin/nstd ] && NSTD="bin/nstd"
BROTLI=""
command -v brotli >/dev/null 2>&1 && BROTLI="brotli"
if [ -z "$NSTD$BROTLI" ]; then echo "note: no bin/nstd and no brotli: writing .gz only" >&2; fi

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
  if [ -n "$NSTD" ]; then
    "$NSTD" -b -9 -c "$f" > "$f.br" 2>/dev/null
    if ! "$NSTD" -d -b -c "$f.br" 2>/dev/null | cmp -s - "$f"; then echo "nstd brotli round trip failed: $f" >&2; exit 1; fi
  elif [ -n "$BROTLI" ]; then
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

if [ -x bin/astroisle ]; then
  echo
  # Budgets: initial JS, lazy chunks, CSS. Reads dist/ only; changes nothing.
  bin/astroisle audit --dist dist --budget-initial 104 --budget-lazy 70 --budget-css 14 || { echo "size budget exceeded" >&2; exit 1; }
fi
echo
echo "Restart to serve it:  systemctl --user restart adimusic"
