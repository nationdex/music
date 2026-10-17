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

{
  echo "listen $host:$port;"
  echo "set \$youtube_key \"$key\";"
} > run/listen.conf
