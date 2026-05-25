#!/usr/bin/env bash
set -euo pipefail

HOST="gateway-vm"
HOST_IP="10.2.20.112"
REMOTE_USER="smoke"
TCP_PORTS=(22 53 80 853 5380 53443)
UDP_PORTS=(53 69 41641)
KEY_UNITS=(
  traefik.service
  technitium-dns-server.service
  atftpd.service
  netbird.service
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

printf 'Checking %s hostname state...\n' "$HOST"
hostname_output="$(ssh_gateway_vm 'hostnamectl --static; hostnamectl --transient')" || die "unable to read hostname state"
printf '%s\n' "$hostname_output"

static_hostname="$(printf '%s\n' "$hostname_output" | sed -n '1p')"
transient_hostname="$(printf '%s\n' "$hostname_output" | sed -n '2p')"

[[ "$static_hostname" == "$HOST" ]] || die "static hostname is '$static_hostname', expected '$HOST'"
[[ "$transient_hostname" == "$HOST" ]] || die "transient hostname is '$transient_hostname', expected '$HOST'"

printf 'Checking gateway units...\n'
for unit in "${KEY_UNITS[@]}"; do
  wait_for_remote "$unit is not active" "systemctl is-active --quiet '$unit'"
  printf '  %s active\n' "$unit"
done

printf 'Checking listening TCP ports...\n'
for port in "${TCP_PORTS[@]}"; do
  wait_for_remote "TCP $port is not listening" "sudo ss -ltn '( sport = :$port )' | grep -q ':$port'"
  printf '  tcp/%s listening\n' "$port"
done

printf 'Checking listening UDP ports...\n'
for port in "${UDP_PORTS[@]}"; do
  wait_for_remote "UDP $port is not listening" "sudo ss -lun '( sport = :$port )' | grep -q ':$port'"
  printf '  udp/%s listening\n' "$port"
done

printf 'Checking NetBird WireGuard configuration...\n'
wait_for_remote "NetBird WireGuard port is not configured" \
  "sudo grep -Eq '\"WgPort\"[[:space:]]*:[[:space:]]*51820' /var/lib/netbird/config.json"
printf '  netbird WgPort configured for udp/51820\n'

printf 'Checking Traefik and Technitium local HTTP endpoints...\n'
wait_for_remote "Traefik dashboard route failed" "curl -fsS -H 'Host: traefik.home.arpa' http://127.0.0.1/dashboard/ >/dev/null"
wait_for_remote "Technitium route failed" "curl -fsS -H 'Host: technitium.home.arpa' http://127.0.0.1/ >/dev/null"

printf 'Running gateway state backup and restore validation...\n'
ssh_gateway_vm "sudo systemctl start gateway-state-backup.service" || die "gateway-state-backup.service failed"
ssh_gateway_vm "sudo systemctl start gateway-state-restore-check.service" || die "gateway-state-restore-check.service failed"

printf 'gateway-vm validation completed.\n'
