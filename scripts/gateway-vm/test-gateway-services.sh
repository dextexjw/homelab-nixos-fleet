#!/usr/bin/env bash
set -euo pipefail

HOST="gateway-vm"
HOST_IP="10.2.20.112"
REMOTE_USER="smoke"
EXTERNAL_TCP_PORTS=(22 53 80 853 5380 8080 53443)
UDP_PORTS=(53 69 41641)
KEY_UNITS=(
  traefik.service
  technitium-dns-server.service
  atftpd.service
  tailscaled.service
  gateway-state-backup.timer
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
}

wait_for_remote() {
  local description="$1"
  local command="$2"

  for attempt in {1..60}; do
    if ssh_gateway_vm "$command"; then
      return 0
    fi

    if [[ "$attempt" == 60 ]]; then
      die "$description"
    fi

    sleep 1
  done
}

ssh_gateway_vm() {
  ssh \
    -o BatchMode=yes \
    -o CheckHostIP=no \
    -o ConnectTimeout=5 \
    -o GlobalKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UpdateHostKeys=no \
    -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$HOST_IP" \
    "$@"
}

need ssh
need dig

printf 'Checking %s hostname state...\n' "$HOST"
hostname_output="$(ssh_gateway_vm 'hostnamectl --static; hostnamectl --transient')" || die "unable to read hostname state"
printf '%s\n' "$hostname_output"

static_hostname="$(printf '%s\n' "$hostname_output" | sed -n '1p')"
transient_hostname="$(printf '%s\n' "$hostname_output" | sed -n '2p')"

[[ "$static_hostname" == "$HOST" ]] || die "static hostname is '$static_hostname', expected '$HOST'"
[[ "$transient_hostname" == "$HOST" ]] || die "transient hostname is '$transient_hostname', expected '$HOST'"

CHECK_NETBIRD=0
if ssh_gateway_vm "systemctl list-unit-files 'netbird.service' --no-legend 2>/dev/null | grep -q '^netbird[.]service'"; then
  CHECK_NETBIRD=1
  KEY_UNITS+=(netbird.service)
fi

printf 'Checking gateway units...\n'
for unit in "${KEY_UNITS[@]}"; do
  wait_for_remote "$unit is not active" "systemctl is-active --quiet '$unit'"
  printf '  %s active\n' "$unit"
done

printf 'Checking externally exposed TCP listeners...\n'
for port in "${EXTERNAL_TCP_PORTS[@]}"; do
  wait_for_remote "TCP $port is not externally listening" "sudo ss -ltn '( sport = :$port )' | grep -Eq '([[:space:]]|^)(${HOST_IP}|0[.]0[.]0[.]0|\\*|\\[::\\]):$port'"
  printf '  tcp/%s listening\n' "$port"
done

printf 'Checking listening UDP ports...\n'
for port in "${UDP_PORTS[@]}"; do
  wait_for_remote "UDP $port is not listening" "sudo ss -lun '( sport = :$port )' | grep -q ':$port'"
  printf '  udp/%s listening\n' "$port"
done

if [[ "$CHECK_NETBIRD" == 1 ]]; then
  printf 'Checking NetBird WireGuard configuration...\n'
  wait_for_remote "NetBird WireGuard port is not configured" \
    "sudo grep -Eq '\"WgPort\"[[:space:]]*:[[:space:]]*51820' /var/lib/netbird/config.json"
  printf '  netbird WgPort configured for udp/51820\n'
else
  printf 'Skipping NetBird checks; netbird.service is not installed on %s\n' "$HOST"
fi

printf 'Checking .h service DNS records...\n'
check_dns_record() {
  local name="$1"
  local expected_ip="$2"

  for attempt in {1..60}; do
    if dig @"$HOST_IP" "$name" +short | grep -Fxq "$expected_ip"; then
      printf '  %s resolves to %s\n' "$name" "$expected_ip"
      return 0
    fi

    if [[ "$attempt" == 60 ]]; then
      die "$name does not resolve to $expected_ip through gateway DNS"
    fi

    sleep 1
  done
}

check_dns_record audiobookshelf.h "$HOST_IP"
check_dns_record jellyfin.h "$HOST_IP"
check_dns_record kavita.h "$HOST_IP"
check_dns_record technitium.h "$HOST_IP"
check_dns_record traefik.h "$HOST_IP"

printf 'Checking Traefik and Technitium local HTTP endpoints...\n'
wait_for_remote "Traefik dashboard web route failed" "curl -fsS -H 'Host: traefik.h' http://127.0.0.1/dashboard/ >/dev/null"
wait_for_remote "Traefik dashboard route failed" "curl -fsS http://127.0.0.1:8080/dashboard/ >/dev/null"
wait_for_remote "Traefik metrics endpoint failed" "curl -fsS http://127.0.0.1:8080/metrics | grep -q '^traefik_'"
wait_for_remote "Jellyfin route failed" "curl -fsS -o /dev/null -H 'Host: jellyfin.h' http://127.0.0.1/"
wait_for_remote "Kavita route failed" "curl -fsS -o /dev/null -H 'Host: kavita.h' http://127.0.0.1/"
wait_for_remote "Technitium route failed" "curl -fsS -H 'Host: technitium.h' http://127.0.0.1/ >/dev/null"

printf 'Running gateway state backup and restore validation...\n'
ssh_gateway_vm "sudo systemctl start gateway-state-backup.service" || die "gateway-state-backup.service failed"
ssh_gateway_vm "sudo systemctl start gateway-state-restore-check.service" || die "gateway-state-restore-check.service failed"

printf 'gateway-vm validation completed.\n'
