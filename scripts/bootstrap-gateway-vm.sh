#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="gateway-vm"
HOST_IP="10.2.20.112"
REMOTE_USER="smoke"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/bootstrap-gateway-vm.sh run
  scripts/bootstrap-gateway-vm.sh check-local-readiness
  scripts/bootstrap-gateway-vm.sh enable-vm-secret-access
  scripts/bootstrap-gateway-vm.sh dry-activate-gateway-vm
  scripts/bootstrap-gateway-vm.sh deploy-gateway-vm
  scripts/bootstrap-gateway-vm.sh verify-gateway-vm

This orchestrates the post-install gateway-vm bootstrap. Run the external
nixos-anywhere install first, then confirm SSH works for ${REMOTE_USER}@${HOST_IP}.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
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

confirm_ssh_access() {
  need ssh

  printf 'Confirming non-interactive SSH access to %s@%s...\n' "$REMOTE_USER" "$HOST_IP"
  ssh_gateway_vm true || die "unable to reach $REMOTE_USER@$HOST_IP with non-interactive SSH"
}

ensure_vm_hostname() {
  need ssh

  printf 'Ensuring %s transient hostname matches deployed hostname...\n' "$HOST"
  ssh_gateway_vm "sudo hostnamectl --transient set-hostname '$HOST'" || die "unable to set transient hostname on $HOST_IP"
}

phase_check_local_readiness() {
  "$ROOT/scripts/bootstrap-gateway.sh"
}

phase_enable_vm_secret_access() {
  "$ROOT/scripts/update-gateway-sops-recipient.sh"
}

phase_dry_activate_gateway_vm() {
  need colmena

  colmena apply --on "$HOST" dry-activate
}

phase_deploy_gateway_vm() {
  "$ROOT/scripts/deploy-gateway.sh"
  ensure_vm_hostname
}

phase_verify_gateway_vm() {
  "$ROOT/scripts/test-gateway-services.sh"
}

run_phase() {
  local name="$1"
  shift

  printf '\n==> %s\n' "$name"
  "$@"
}

run_all() {
  run_phase check-local-readiness phase_check_local_readiness
  run_phase confirm-ssh-access confirm_ssh_access
  run_phase enable-vm-secret-access phase_enable_vm_secret_access
  run_phase dry-activate-gateway-vm phase_dry_activate_gateway_vm
  run_phase deploy-gateway-vm phase_deploy_gateway_vm
  run_phase verify-gateway-vm phase_verify_gateway_vm

  printf '\ngateway-vm bootstrap completed.\n'
}

cd "$ROOT"

command="${1:-}"
case "$command" in
  run)
    shift
    [[ $# -eq 0 ]] || die "run does not accept arguments"
    run_all
    ;;
  check-local-readiness)
    shift
    [[ $# -eq 0 ]] || die "check-local-readiness does not accept arguments"
    phase_check_local_readiness
    ;;
  enable-vm-secret-access)
    shift
    [[ $# -eq 0 ]] || die "enable-vm-secret-access does not accept arguments"
    phase_enable_vm_secret_access
    ;;
  dry-activate-gateway-vm)
    shift
    [[ $# -eq 0 ]] || die "dry-activate-gateway-vm does not accept arguments"
    phase_dry_activate_gateway_vm
    ;;
  deploy-gateway-vm)
    shift
    [[ $# -eq 0 ]] || die "deploy-gateway-vm does not accept arguments"
    phase_deploy_gateway_vm
    ;;
  verify-gateway-vm)
    shift
    [[ $# -eq 0 ]] || die "verify-gateway-vm does not accept arguments"
    phase_verify_gateway_vm
    ;;
  -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $command"
    ;;
esac
