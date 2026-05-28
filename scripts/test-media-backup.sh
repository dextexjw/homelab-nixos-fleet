#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="media-vm"
HOST_IP="10.2.20.113"
REPOSITORY="/mnt/backups/restic/appdata/media-stack-vm"
SOURCE="/srv/appsdata"
RUN_KILL_SWITCH=false

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/test-media-backup.sh [--include-kill-switch]

Runs MediaVM backup, restore, Gluetun, qBittorrent, and container isolation
checks. The kill-switch check briefly stops MediaVM Gluetun and qBittorrent.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-kill-switch)
      RUN_KILL_SWITCH=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"
command -v curl >/dev/null 2>&1 || die "curl is missing"

cd "$ROOT"

colmena exec --on "$HOST" -- "sh -lc 'findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups'"
colmena exec --on "$HOST" -- systemctl start appsdata-backup.service
colmena exec --on "$HOST" -- systemctl start appsdata-restore-check.service
colmena exec --on "$HOST" -- systemctl is-active appsdata-backup.timer
colmena exec --on "$HOST" -- env \
  RESTIC_REPOSITORY="$REPOSITORY" \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host "$HOST" --path "$SOURCE" --tag appsdata --latest 3

for unit in podman-media-gluetun podman-media-qbittorrent podman-media-gluetun-webui; do
  colmena exec --on "$HOST" -- systemctl is-active --quiet "$unit.service" || die "$unit.service is not active"
done

curl -fsS "http://$HOST_IP:8080/" >/dev/null || die "qBittorrent WebUI is not reachable through MediaVM Gluetun"
curl -fsS "http://$HOST_IP:3001/api/health" >/dev/null || die "MediaVM Gluetun WebUI health endpoint is not reachable"

colmena exec --on "$HOST" -- "sh -lc 'gluetun_id=\$(podman inspect --format \"{{.Id}}\" media-gluetun); network_mode=\$(podman inspect --format \"{{.HostConfig.NetworkMode}}\" media-qbittorrent); test \"\$network_mode\" = container:media-gluetun || test \"\$network_mode\" = \"container:\$gluetun_id\"'" \
  || die "media-qbittorrent is not sharing the media-gluetun network namespace"
colmena exec --on "$HOST" -- "sh -lc 'test \"\$(podman inspect --format \"{{json .HostConfig.PortBindings}}\" media-qbittorrent)\" = \"{}\"'" \
  || die "media-qbittorrent unexpectedly declares host port bindings"
colmena exec --on "$HOST" -- "sh -lc 'podman port media-gluetun | grep -Fq \"8080/tcp\" && podman port media-gluetun | grep -Fq \"3001/tcp\"'" \
  || die "media-gluetun is not publishing the expected qBittorrent and Gluetun WebUI ports"

if "$RUN_KILL_SWITCH"; then
  cleanup_kill_switch() {
    colmena exec --on "$HOST" -- sudo systemctl unmask podman-media-gluetun.service >/dev/null 2>&1 || true
    colmena exec --on "$HOST" -- sudo systemctl start podman-media-gluetun.service >/dev/null 2>&1 || true
    colmena exec --on "$HOST" -- sudo systemctl start podman-media-qbittorrent.service podman-media-gluetun-webui.service >/dev/null 2>&1 || true
  }
  trap cleanup_kill_switch EXIT

  colmena exec --on "$HOST" -- sudo systemctl stop podman-media-gluetun.service
  colmena exec --on "$HOST" -- "sh -lc '! systemctl is-active --quiet podman-media-qbittorrent.service'" \
    || die "qBittorrent stayed active after MediaVM Gluetun stopped"
  if curl -fsS --max-time 5 "http://$HOST_IP:8080/" >/dev/null 2>&1; then
    die "qBittorrent WebUI stayed reachable after MediaVM Gluetun stopped"
  fi

  colmena exec --on "$HOST" -- sudo systemctl mask --runtime podman-media-gluetun.service
  colmena exec --on "$HOST" -- "sh -lc 'systemctl start --no-block podman-media-qbittorrent.service >/dev/null 2>&1 || true; sleep 5; ! systemctl is-active --quiet podman-media-qbittorrent.service'" \
    || die "qBittorrent became active while MediaVM Gluetun was runtime-masked"
  if curl -fsS --max-time 5 "http://$HOST_IP:8080/" >/dev/null 2>&1; then
    die "qBittorrent WebUI became reachable while MediaVM Gluetun was runtime-masked"
  fi

  cleanup_kill_switch
  trap - EXIT

  for unit in podman-media-gluetun podman-media-qbittorrent podman-media-gluetun-webui; do
    colmena exec --on "$HOST" -- systemctl is-active --quiet "$unit.service" || die "$unit.service did not recover after kill-switch validation"
  done
fi
