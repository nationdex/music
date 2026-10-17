#!/bin/sh
# Install the Adi Music user service. Idempotent; safe to re-run.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"

command -v systemctl >/dev/null 2>&1 || { echo "systemctl not available" >&2; exit 1; }
command -v nginx >/dev/null 2>&1 || { echo "nginx not available (apt install nginx; the system service can stay disabled)" >&2; exit 1; }

mkdir -p "$UNIT_DIR"
cp "$HERE/adimusic.service" "$UNIT_DIR/adimusic.service"

systemctl --user daemon-reload
systemctl --user enable adimusic.service

echo "Installed. Start with:  systemctl --user restart adimusic"
echo "Config:                $HERE/adimusic.env"
echo "Logs:                  journalctl --user -u adimusic -f"
