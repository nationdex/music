# Sourced by prepare.sh and optimize.sh: a short content hash of a directory tree.
# Precompressed copies and the marker file are left out, so the hash only changes with real content.
tree_hash() {
  (cd "$1" && find . -type f ! -name '*.gz' ! -name '*.br' ! -name '.source-hash' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12)
}
