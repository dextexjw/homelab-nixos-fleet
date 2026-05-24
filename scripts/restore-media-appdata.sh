#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="media-vm"
REPOSITORY="/mnt/backups/restic/appdata/media-stack-vm"
SOURCE="/srv/appsdata"
TAG="appsdata"
SERVICES="jellyfin audiobookshelf kavita radarr sonarr prowlarr bazarr qbittorrent sabnzbd jellyseerr flaresolverr"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"
command -v base64 >/dev/null 2>&1 || die "base64 is missing"

cd "$ROOT"

remote_script="$(
  cat <<SCRIPT
set -euo pipefail

repository='${REPOSITORY}'
source_path='${SOURCE}'
tag='${TAG}'
services='${SERVICES}'

export RESTIC_REPOSITORY="\$repository"
export RESTIC_PASSWORD_FILE=/run/secrets/restic-password

echo 'Stopping media services before appdata restore...'
systemctl stop appsdata-backup.timer \$services

echo 'Mounting /mnt/backups...'
findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups

if [ ! -r "\$RESTIC_PASSWORD_FILE" ]; then
  echo "\$RESTIC_PASSWORD_FILE is not readable; cannot inspect or restore appdata" >&2
  systemctl start \$services
  systemctl start appsdata-backup.timer
  exit 1
fi

if [ ! -d "\$repository/data" ]; then
  echo "No initialized Restic repository found at \$repository; continuing as a fresh system."
  systemctl start \$services
  systemctl start appsdata-backup.timer
  exit 0
fi

if ! restic snapshots --host '${HOST}' --path "\$source_path" --tag "\$tag" >/tmp/appsdata-snapshots.txt; then
  echo 'Unable to inspect Restic snapshots; leaving media services stopped for investigation.' >&2
  cat /tmp/appsdata-snapshots.txt >&2 || true
  exit 1
fi

if ! grep -q '^ID ' /tmp/appsdata-snapshots.txt; then
  echo "No matching Restic snapshot found for host=${HOST}, path=\$source_path, tag=\$tag; continuing as a fresh system."
  systemctl start \$services
  systemctl start appsdata-backup.timer
  exit 0
fi

cat /tmp/appsdata-snapshots.txt

echo 'Restoring latest appdata snapshot to /...'
restic restore latest \
  --host '${HOST}' \
  --path "\$source_path" \
  --tag "\$tag" \
  --target / \
  --verify

echo 'Reapplying declared directories and restarting media services...'
systemd-tmpfiles --create
systemctl start \$services
systemctl start appsdata-backup.timer
systemctl start appsdata-restore-check.service

echo 'media-vm appdata restore flow complete.'
SCRIPT
)"

remote_script_b64="$(printf '%s' "$remote_script" | base64 --wrap=0)"

colmena exec --on "$HOST" -- "printf '%s' '$remote_script_b64' | base64 -d | sudo bash"
