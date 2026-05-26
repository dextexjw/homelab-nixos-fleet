# gateway-vm

`gateway-vm` runs Traefik ingress, Technitium DNS, netboot.xyz, NetBird, and
Tailscale.

Fleet inventory lives in `../../hosts.nix`. Host configuration lives in
`configuration.nix` and imports service modules from `../../modules/gateway/`.

## Host Model

Important host values:

- FQDN: `gateway.home.arpa`
- IP: `10.2.20.112`
- Gateway: `10.2.20.1`
- DNS: `10.2.20.1`, `9.9.9.9`
- Time zone: `America/New_York`
- Admin user: `smoke`
- VM disk: `/dev/sda`
- VM RAM: `8 GB`
- VM CPU cores: `4`

State paths:

- `/srv/appsdata/technitium-dns-server`
- `/srv/appsdata/netbird`
- `/srv/appsdata/tailscale`

Gateway state is backed up with Restic to
`/mnt/backup/restic/appdata/gateway-vm`. The restore-check target is
`/var/tmp/gateway-state-restore-check`.

## Service Access

Direct service ports:

- Traefik HTTP ingress: `http://10.2.20.112`
- Traefik HTTPS ingress: `https://10.2.20.112`
- Traefik dashboard: `http://10.2.20.112:8080/dashboard/`
- Traefik Prometheus metrics: `http://10.2.20.112:8080/metrics`
- DNS: `10.2.20.112:53` over TCP and UDP
- DNS-over-TLS: `10.2.20.112:853`
- Technitium admin HTTP: `http://10.2.20.112:5380`
- Technitium HTTPS and DNS-over-HTTPS: `https://10.2.20.112:53443`
- netboot.xyz TFTP: `10.2.20.112:69/udp`, boot file `netboot.xyz.efi`
- NetBird: disabled for now; state preserved at `/srv/appsdata/netbird`
- Tailscale: `10.2.20.112:41641/udp`

Technitium admin HTTP is available directly at `http://10.2.20.112:5380` and
through Traefik at `http://technitium.home.arpa/`.

Traefik writes JSON access logs to the `traefik.service` journal. Prometheus
metrics are exposed on the existing dashboard entrypoint at
`http://10.2.20.112:8080/metrics`. OpenTelemetry tracing is declared in the
Gateway Traefik module but should only be enabled after an OTLP collector
endpoint is available.

`gateway-vm` intentionally pins Traefik to the upstream `3.7.1` Linux AMD64
release artifact and Technitium DNS to the upstream `15.2.0` source release
while the rest of the fleet remains on the locked `nixpkgs` package set.

Technitium serves the `home.arpa` zone and points `*.home.arpa` at
`10.2.20.112` for Traefik ingress. Clients must use `10.2.20.112` as DNS, or
the LAN DNS/DHCP server must forward/delegate `home.arpa` to `10.2.20.112`, for
these names to resolve.

If a browser shows `DNS_PROBE_FINISHED_NXDOMAIN` for a `home.arpa` name, confirm
whether the client is asking Gateway DNS:

```sh
dig technitium.home.arpa
dig @10.2.20.112 technitium.home.arpa
```

The first command must query `10.2.20.112`, or the LAN DNS server must have a
conditional forward/delegation for `home.arpa` to `10.2.20.112`. A temporary
single-client workaround is adding `10.2.20.112 technitium.home.arpa` to that
client's hosts file.

Traefik ingress routes are declared for:

- `technitium.home.arpa`
- `jellyfin.home.arpa`
- `audiobookshelf.home.arpa`
- `kavita.home.arpa`
- `sonarr.home.arpa`
- `radarr.home.arpa`
- `prowlarr.home.arpa`
- `bazarr.home.arpa`
- `qbittorrent.home.arpa`
- `sabnzbd.home.arpa`
- `jellyseerr.home.arpa`

For netboot.xyz, configure the LAN DHCP server to point option 66 at
`10.2.20.112` and option 67 at `netboot.xyz.efi`. `gateway-vm` serves TFTP but
does not take over DHCP for the subnet.

## Secrets

Required secrets:

- `admin-password-hash`
- `smb-credentials`
- `restic-password`
- `technitium-admin-username`
- `technitium-admin-password`

Normal edit flow:

```sh
nix develop
sops secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

`gateway-vm` decrypts secrets using `/etc/ssh/ssh_host_ed25519_key`. After a
new VM install or host key change, capture the host recipient:

```sh
ssh smoke@10.2.20.112 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
```

Add the printed `age1...` recipient to `.sops.yaml`, then rekey:

```sh
sops updatekeys secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

Keep `restic-password` stable. It is the encryption key for the Restic
repository; changing it makes existing snapshots unreadable with the new value.

## Bootstrap

Use this flow after preparing a fresh `gateway-vm` install. The destructive
`nixos-anywhere` VM install is managed outside this fleet repo before
declarative deployment begins.

```sh
nix develop
scripts/gateway-vm/bootstrap-gateway-vm.sh run
```

The bootstrap phases are resumable:

- `check-local-readiness`: verifies tools, encrypted secrets, `nix flake check`, and `colmena build --on gateway-vm`.
- `enable-vm-secret-access`: captures the gateway SSH host key, adds the age recipient to `.sops.yaml`, and runs `sops updatekeys`.
- `dry-activate-gateway-vm`: validates the activation plan with `colmena apply --on gateway-vm dry-activate`.
- `deploy-gateway-vm`: runs the guarded gateway deployment.
- `verify-gateway-vm`: confirms hostnames, service health, listener ports, Traefik routes, and Restic backup/restore validation.

Individual phases:

```sh
scripts/gateway-vm/bootstrap-gateway-vm.sh check-local-readiness
scripts/gateway-vm/bootstrap-gateway-vm.sh enable-vm-secret-access
scripts/gateway-vm/bootstrap-gateway-vm.sh dry-activate-gateway-vm
scripts/gateway-vm/bootstrap-gateway-vm.sh deploy-gateway-vm
scripts/gateway-vm/bootstrap-gateway-vm.sh verify-gateway-vm
```

## Upgrade

Use this flow for an already-running `gateway-vm`. It deploys the current repo
state only; update and review `flake.lock` or host-local package pins
separately before running it.

```sh
nix develop
scripts/gateway-vm/upgrade-gateway-vm.sh run
```

The wrapper runs these phases in order:

- `check-upgrade-readiness`: verifies dev-shell tools, encrypted secrets, non-interactive SSH, `nix flake check`, and `colmena build --on gateway-vm`.
- `create-pre-upgrade-backup`: starts a gateway appdata Restic backup and lists the latest matching snapshots.
- `dry-activate-gateway-vm`: validates the activation plan with `colmena apply --on gateway-vm dry-activate`.
- `deploy-gateway-vm`: runs the guarded `gateway-vm` deployment and normalizes the transient hostname.
- `verify-gateway-vm`: confirms service health, listener ports, Traefik routes, DNS records, backup/restore validation, and tmpfiles declarations.

The upgrade workflow never restores appdata automatically. Use the restore
workflow only when recovering from a failed host or bad application state.

The phases can also be run individually:

```sh
scripts/gateway-vm/upgrade-gateway-vm.sh check-upgrade-readiness
scripts/gateway-vm/upgrade-gateway-vm.sh create-pre-upgrade-backup
scripts/gateway-vm/upgrade-gateway-vm.sh dry-activate-gateway-vm
scripts/gateway-vm/upgrade-gateway-vm.sh deploy-gateway-vm
scripts/gateway-vm/upgrade-gateway-vm.sh verify-gateway-vm
```

## Deploy

Use plain Colmena commands from inside `nix develop`.

```sh
colmena build --on gateway-vm
colmena apply --on gateway-vm dry-activate
colmena apply --on gateway-vm switch
```

The guarded deploy helper checks local SOPS decryption and confirms the VM has
a matching SOPS recipient before switching:

```sh
scripts/gateway-vm/deploy-gateway.sh
```

## Backups and Restore

`gateway-vm` backs up `/srv/appsdata` with Restic.

- Service: `gateway-state-backup.service`
- Timer: `gateway-state-backup.timer`
- Source: `/srv/appsdata`
- Repository: `/mnt/backup/restic/appdata/gateway-vm`
- Password file: `/run/secrets/restic-password`
- Non-destructive restore validation: `gateway-state-restore-check.service`

Post-deploy validation:

```sh
scripts/gateway-vm/test-gateway-services.sh
```

That script verifies service health, listener ports, Traefik routes, and
gateway state backup/restore validation.

Manual backup and restore validation on `gateway-vm`:

```sh
mount /mnt/backup
systemctl start gateway-state-backup.service
systemctl start gateway-state-restore-check.service
systemctl status gateway-state-backup.service gateway-state-restore-check.service
```

Restore outline:

1. Deploy `gateway-vm` once to create users, secrets, mounts, and units.
2. Stop Technitium, NetBird, and Tailscale before replacing state.
3. Mount `/mnt/backup`.
4. Choose a `gateway-vm` appdata snapshot ID.
5. Restore the snapshot to `/` with `restic --verify`.
6. Run `systemd-tmpfiles --create`.
7. Restart `technitium-dns-server.service` and `tailscaled.service`; restart `netbird.service` too if NetBird is re-enabled.

The same service and recovery model is generated on `gateway-vm` at
`/etc/fleet/gateway-vm.md`. Keep this README and the generated recovery notes
in sync when backup or restore behavior changes.

## Operations

Check service status through Colmena:

```sh
colmena exec --on gateway-vm -- systemctl status traefik
colmena exec --on gateway-vm -- systemctl status technitium-dns-server
colmena exec --on gateway-vm -- systemctl status atftpd
colmena exec --on gateway-vm -- systemctl status tailscaled
colmena exec --on gateway-vm -- systemctl status gateway-state-backup.timer
```

Roll back a NixOS generation from the host:

```sh
sudo nixos-rebuild switch --rollback
```

You can also reboot and choose an earlier generation from the bootloader.

## Safety Notes

- `hosts.nix` declares the `gateway-vm` disk as `/dev/sda`; any installer or partitioning command against that disk is destructive.
- `gateway-vm` serves TFTP for netboot.xyz but does not take over DHCP for the subnet.
- Keep auth keys and service secrets in encrypted secrets only.
- Do not write plaintext secrets into Nix files, generated configs, recovery notes, logs, or chat.
