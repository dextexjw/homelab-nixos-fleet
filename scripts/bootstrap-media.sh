#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="media-vm"
SECRETS="$ROOT/secrets/secrets.yaml"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need nix
need sops
need ssh

cd "$ROOT"

if [[ ! -f "$SECRETS" ]]; then
  die "missing $SECRETS; copy secrets/example-secrets.yaml, fill it, then encrypt it with sops"
fi

if ! grep -q '^sops:' "$SECRETS"; then
  die "$SECRETS does not look encrypted by sops"
fi

if ! decrypted_secrets="$(sops --decrypt "$SECRETS")"; then
  die "unable to decrypt $SECRETS; rekey it for your local key before bootstrap checks"
fi

if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
  die "$SECRETS still contains CHANGE_ME placeholders"
fi

nix flake check
colmena build --on "$HOST"

cat <<MSG
Bootstrap checks passed for $HOST.

Next steps:
  1. Install NixOS on the VM disk with the destructive installer flow you trust.
  2. Ensure SSH for smoke works at 10.2.20.113.
  3. Add the VM SSH host recipient to .sops.yaml and rekey secrets:
       scripts/update-media-sops-recipient.sh
  4. Run: scripts/deploy-media.sh
  5. Confirm hostname state:
       ssh smoke@10.2.20.113 'hostnamectl --static; hostnamectl --transient'
     If the transient hostname still shows the bootstrap name, reboot once or run:
       ssh smoke@10.2.20.113 'sudo hostnamectl --transient hostname media-vm'
MSG
