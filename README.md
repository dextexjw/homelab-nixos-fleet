# Homelab NixOS Fleet

This repository is my personal NixOS homelab fleet. It is managed as a Nix
flake and deployed with Colmena.

The current shape is intentionally small:

- `media-vm` runs the media stack, SMB mounts, appdata backups, and restore checks.
- `gateway-vm` runs Traefik ingress, Technitium DNS, netboot.xyz, NetBird, and Tailscale.

Treat it as the source of truth for my own hosts, services, secrets workflow,
and recovery notes.

The fleet-wide service standard is captured in
`PRINCIPLES.md`. New Gateway, Security, Identity, and
other service modules should follow that blueprint before being treated as
production-ready.

## Current Hosts

| Host | IP | Tags | Role |
| --- | --- | --- | --- |
| `gateway-vm` | `10.2.20.112` | `control-plane`, `gateway` | Traefik, Technitium DNS, netboot.xyz, NetBird, Tailscale |
| `media-vm` | `10.2.20.113` | `media` | Jellyfin, Audiobookshelf, Kavita, ARR stack, downloads, SMB media, Restic appdata backups |

Inventory lives in `hosts.nix`. Per-host configuration lives under
`hosts/<name>/`.

## Repository Map

- `flake.nix`: inputs, development shell, and Colmena hive.
- `hosts.nix`: host IPs, users, tags, and `media-vm` constants.
- `hosts/common.nix`: shared Nix, SSH, user, firewall, package, and node-exporter defaults.
- `hosts/gateway-vm/`: gateway host configuration and hardware profile.
- `hosts/media-vm/`: media host configuration and hardware profile.
- `modules/gateway/`: Traefik, Technitium, netboot.xyz, NetBird, and Tailscale modules.
- `modules/media/stack.nix`: the main `media-vm` service stack, SMB mounts, backups, and recovery notes.
- `modules/monitoring/`: available Prometheus, Grafana, and node exporter modules.
- `modules/networking/reverse-proxy.nix`: available nginx virtual hosts module.
- `modules/security/self-signed-ca.nix`: internal self-signed CA and per-domain cert generation.
- `modules/dev/`: available Jenkins and Gitea modules.
- `modules/apps/freshrss.nix`: available module, not currently enabled.
- `secrets/example-secrets.yaml`: expected SOPS secret shape.
- `secrets/secrets.yaml`: encrypted real secrets.
- `scripts/`: local helper scripts for checks, media deploys, bootstrap, backup validation, and appdata restore.

## Local Workflow

Enter the development shell before using Colmena, SOPS, age, Restic, or the
helper scripts:

```sh
nix develop
```

With `direnv`, `.envrc` loads the same flake shell automatically.

Useful local checks:

```sh
nix flake check
colmena build --on media-vm
colmena apply --on media-vm dry-activate
```

The repo also has a focused check helper:

```sh
scripts/check.sh
```

## Deployments

Use plain Colmena commands from inside `nix develop`.

Deploy one host:

```sh
colmena apply --on media-vm switch
colmena apply --on gateway-vm switch
```

Deploy by tag only when intentionally targeting a group:

```sh
colmena apply --on @media switch
colmena apply --on @gateway switch
```

Deploy the whole fleet only when that is really the goal:

```sh
colmena apply switch
```

For `media-vm`, the guarded deploy helper checks local SOPS decryption and
confirms the VM has a matching SOPS recipient before switching:

```sh
scripts/deploy-media.sh
```

For `gateway-vm`, the guarded deploy helper performs the same SOPS recipient
check before switching:

```sh
scripts/deploy-gateway.sh
```

## Service Access

### media-vm

| Service | URL |
| --- | --- |
| Jellyfin | `http://10.2.20.113:8096` |
| Audiobookshelf | `http://10.2.20.113:8000` |
| Kavita | `http://10.2.20.113:5000` |
| Radarr | `http://10.2.20.113:7878` |
| Sonarr | `http://10.2.20.113:8989` |
| Prowlarr | `http://10.2.20.113:9696` |
| Bazarr | `http://10.2.20.113:6767` |
| qBittorrent | `http://10.2.20.113:8080` |
| SABnzbd | `http://10.2.20.113:8085` |
| Jellyseerr | `http://10.2.20.113:5055` |

FlareSolverr listens on `8191` for app integration and is not opened in the
firewall.

### gateway-vm

Direct service ports:

- DNS: `10.2.20.112:53` over TCP and UDP
- DNS-over-TLS: `10.2.20.112:853`
- Technitium admin HTTP: `http://10.2.20.112:5380`
- Technitium HTTPS and DNS-over-HTTPS: `https://10.2.20.112:53443`
- netboot.xyz TFTP: `10.2.20.112:69/udp`, boot file `netboot.xyz.efi`
- NetBird: `10.2.20.112:51820/udp`
- Tailscale: `10.2.20.112:41641/udp`

Traefik routes are declared for:

- `traefik.home.arpa`
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

## gateway-vm Model

`gateway-vm` is configured from `hosts/gateway-vm/configuration.nix` and
`modules/gateway/`.

Important host values:

- FQDN: `gateway.home.arpa`
- Gateway: `10.2.20.1`
- DNS: `10.2.20.1`, `9.9.9.9`
- Time zone: `America/New_York`
- Admin user: `smoke`
- VM disk: `/dev/sda`

State paths:

- `/srv/appsdata/technitium-dns-server`
- `/srv/appsdata/netbird`
- `/srv/appsdata/tailscale`

Gateway state is backed up with Restic to
`/mnt/backup/restic/appdata/gateway-vm`. The restore-check target is
`/var/tmp/gateway-state-restore-check`.

## gateway-vm Bootstrap

Use this flow after preparing a fresh `gateway-vm` install. The destructive
`nixos-anywhere` VM install is managed outside this fleet repo before
declarative deployment begins.

```sh
nix develop
scripts/bootstrap-gateway-vm.sh run
```

The bootstrap phases are resumable:

- `check-local-readiness`: verifies tools, encrypted secrets, `nix flake check`,
  and `colmena build --on gateway-vm`.
- `enable-vm-secret-access`: captures the gateway SSH host key, adds the age
  recipient to `.sops.yaml`, and runs `sops updatekeys`.
- `dry-activate-gateway-vm`: validates the activation plan with
  `colmena apply --on gateway-vm dry-activate`.
- `deploy-gateway-vm`: runs the guarded gateway deployment.
- `verify-gateway-vm`: confirms hostnames, service health, listener ports,
  Traefik routes, and Restic backup/restore validation.

Individual phases:

```sh
scripts/bootstrap-gateway-vm.sh check-local-readiness
scripts/bootstrap-gateway-vm.sh enable-vm-secret-access
scripts/bootstrap-gateway-vm.sh dry-activate-gateway-vm
scripts/bootstrap-gateway-vm.sh deploy-gateway-vm
scripts/bootstrap-gateway-vm.sh verify-gateway-vm
```

## media-vm Model

`media-vm` is configured from `hosts/media-vm/configuration.nix` and
`modules/media/stack.nix`.

Important host values:

- FQDN: `media.home.arpa`
- Gateway: `10.2.20.1`
- DNS: `10.2.20.1`, `1.1.1.1`
- Time zone: `America/New_York`
- Admin user: `smoke`
- VM disk: `/dev/sda`
- VM RAM: `12 GB`
- VM CPU cores: `4`
- Media SMB share: `//nas.home.arpa/media` mounted at `/mnt/media`
- Backup SMB share: `//nas.home.arpa/backups` mounted at `/mnt/backups`

Media files live on the NAS-mounted `/mnt/media` share. Application state lives
under `/srv/appsdata`, which is the restore-critical path backed up by Restic.

Appdata paths:

- `/srv/appsdata/jellyfin`
- `/srv/appsdata/audiobookshelf`
- `/srv/appsdata/kavita`
- `/srv/appsdata/radarr`
- `/srv/appsdata/sonarr`
- `/srv/appsdata/prowlarr`
- `/srv/appsdata/bazarr`
- `/srv/appsdata/qbittorrent`
- `/srv/appsdata/sabnzbd`
- `/srv/appsdata/jellyseerr`
- `/srv/appsdata/flaresolverr`
- `/srv/appsdata/monitoring`

Media library paths:

- Movies: `/mnt/media/MOVIES`, `/mnt/media/NewMovies`
- TV: `/mnt/media/TVshows`
- Kids: `/mnt/media/KidsMedia/KidsMovies`, `/mnt/media/KidsMedia/KidsTVshows`
- Audiobooks: `/mnt/media/Audiobooks`
- Podcasts: `/mnt/media/Podcasts`
- Books and Calibre: `/mnt/media/Books`
- Comics: `/mnt/media/Comics`
- PDFs: `/mnt/media/PDFs`
- Downloads: `/mnt/media/downloads`
- Incomplete downloads: `/mnt/media/downloads/in-progress`

## Secrets

Secrets are managed with SOPS and deployed through `sops-nix`.

Expected secrets:

- `admin-password-hash`
- `smb-credentials`
- `restic-password`
- `qbittorrent-webui-username`
- `qbittorrent-webui-password`

Normal edit flow:

```sh
nix develop
sops secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

If `secrets/secrets.yaml` is missing, start from the example and encrypt it:

```sh
cp secrets/example-secrets.yaml secrets/secrets.yaml
sops --encrypt --in-place secrets/secrets.yaml
```

`media-vm` decrypts secrets using `/etc/ssh/ssh_host_ed25519_key`. After a new
VM install or host key change, capture the host recipient:

```sh
ssh smoke@10.2.20.113 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
```

For `gateway-vm`, use:

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

## media-vm Bootstrap

Use this flow after preparing a fresh `media-vm` install. The destructive
`nixos-anywhere` VM install is managed from the separate installer repo before
this fleet deployment begins.

1. Enter the dev shell and make sure `secrets/secrets.yaml` is filled and
   encrypted.

```sh
nix develop
```

2. Run the external `nixos-anywhere` install for `media-vm`, then confirm
   non-interactive SSH works.

```sh
ssh -o BatchMode=yes smoke@10.2.20.113 true
```

3. Run the guided post-install bootstrap.

```sh
scripts/bootstrap-media-vm.sh run
```

The wrapper runs these phases in order:

- `check-local-readiness`: verifies local tools, encrypted secrets,
  `nix flake check`, and `colmena build --on media-vm`.
- `enable-vm-secret-access`: runs `scripts/update-media-sops-recipient.sh` to
  add the VM SSH host key as a SOPS age recipient and rekey secrets.
- `deploy-media-vm`: runs the guarded `media-vm` deployment and normalizes
  the transient hostname left by the installer.
- `restore-appdata`: restores existing appdata from Restic when a matching
  snapshot exists.
- `verify-media-vm`: confirms hostname state and runs the backup/restore
  validation.

If the restore phase lists multiple matching snapshots, rerun it with the exact
snapshot ID you want to restore:

```sh
scripts/bootstrap-media-vm.sh restore-appdata <snapshot-id>
scripts/bootstrap-media-vm.sh verify-media-vm
```

After a rebuild, avoid tiny fresh-system snapshots and choose the last known good
appdata snapshot from before the rebuild.

The phases can also be run individually:

```sh
scripts/bootstrap-media-vm.sh check-local-readiness
scripts/bootstrap-media-vm.sh enable-vm-secret-access
scripts/bootstrap-media-vm.sh deploy-media-vm
scripts/bootstrap-media-vm.sh restore-appdata [snapshot-id]
scripts/bootstrap-media-vm.sh verify-media-vm
```

To pass a known snapshot through the full bootstrap:

```sh
scripts/bootstrap-media-vm.sh run --snapshot-id <snapshot-id>
```

During verification, both static and transient hostname values should report
`media-vm`.

## media-vm Upgrade

Use this flow for an already-running `media-vm`. It deploys the current repo
state only; update and review `flake.lock` separately before running it.

```sh
nix develop
scripts/upgrade-media-vm.sh run
```

The wrapper runs these phases in order:

- `check-upgrade-readiness`: verifies dev-shell tools, encrypted secrets,
  non-interactive SSH, `nix flake check`, and `colmena build --on media-vm`.
- `create-pre-upgrade-backup`: starts an appdata Restic backup and lists the
  latest matching snapshots.
- `dry-activate-media-vm`: validates the activation plan with
  `colmena apply --on media-vm dry-activate`.
- `deploy-media-vm`: runs the guarded `media-vm` deployment and normalizes the
  transient hostname.
- `verify-media-vm`: confirms hostname state, runs backup/restore validation,
  checks tmpfiles declarations, and verifies key media services are active.

The upgrade workflow never restores appdata automatically. Use the restore
workflow only when recovering from a failed host or bad application state.

The phases can also be run individually:

```sh
scripts/upgrade-media-vm.sh check-upgrade-readiness
scripts/upgrade-media-vm.sh create-pre-upgrade-backup
scripts/upgrade-media-vm.sh dry-activate-media-vm
scripts/upgrade-media-vm.sh deploy-media-vm
scripts/upgrade-media-vm.sh verify-media-vm
```

## Backups and Restore

`media-vm` backs up `/srv/appsdata` with Restic.

- Service: `appsdata-backup.service`
- Timer: `appsdata-backup.timer`
- Source: `/srv/appsdata`
- Repository: `/mnt/backups/restic/appdata/media-stack-vm`
- Password file: `/run/secrets/restic-password`
- Schedule: daily
- Retention: 7 daily, 4 weekly, 6 monthly snapshots
- Restic host: `media-vm`
- Restic tag: `appsdata`
- Non-destructive restore validation: `appsdata-restore-check.service`

Post-deploy validation:

```sh
scripts/test-media-backup.sh
```

That script mounts `/mnt/backups` if needed, starts a backup, starts the restore
check, verifies the timer, and lists the latest tagged snapshots.

Manual backup inspection on `media-vm`:

```sh
systemctl status appsdata-backup.timer
journalctl -u appsdata-backup.service
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host media-vm --path /srv/appsdata --tag appsdata
```

Routine restore validation:

```sh
systemctl start appsdata-restore-check.service
journalctl -u appsdata-restore-check.service
```

Destructive full restore outline:

1. Stop the backup timer and media services.

```sh
systemctl stop appsdata-backup.timer
systemctl stop jellyfin audiobookshelf kavita radarr sonarr prowlarr bazarr qbittorrent sabnzbd jellyseerr flaresolverr
```

2. Mount the backup share.

```sh
mount /mnt/backups
```

3. Confirm snapshots exist.

```sh
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host media-vm --path /srv/appsdata --tag appsdata
```

4. Restore the selected tagged snapshot.

```sh
SNAPSHOT=<snapshot-id>
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic restore "$SNAPSHOT" \
    --host media-vm \
    --path /srv/appsdata \
    --tag appsdata \
    --target / \
    --verify
```

5. Reapply declared directories, normalize ownership for rebuilt users, restart
   services, and validate.

```sh
systemd-tmpfiles --create
systemctl restart kavita-token-key.service
systemctl start jellyfin audiobookshelf kavita radarr sonarr prowlarr bazarr qbittorrent sabnzbd jellyseerr flaresolverr
systemctl start appsdata-backup.timer
systemctl start appsdata-restore-check.service
```

The same recovery outline is generated on `media-vm` at
`/etc/fleet/media-vm.md`.

## Operations

Check service status through Colmena:

```sh
colmena exec --on media-vm -- systemctl status jellyfin
colmena exec --on media-vm -- systemctl status appsdata-backup.timer
colmena exec --on gateway-vm -- systemctl status traefik
colmena exec --on gateway-vm -- systemctl status technitium-dns-server
colmena exec --on gateway-vm -- systemctl status atftpd
colmena exec --on gateway-vm -- systemctl status netbird
colmena exec --on gateway-vm -- systemctl status tailscaled
colmena exec --on gateway-vm -- systemctl status gateway-state-backup.timer
```

Check SMB mounts on `media-vm`:

```sh
mount /mnt/media
ls -la /mnt/media
mount /mnt/backups
ls -la /mnt/backups
```

Roll back a NixOS generation from the host:

```sh
sudo nixos-rebuild switch --rollback
```

You can also reboot and choose an earlier generation from the bootloader.

## Changing the Fleet

Service modules live under `modules/<domain>/` and expose options under the
`fleet.<domain>.<service>` namespace. Follow the existing module shape:

1. Define options under `options`.
2. Gate implementation with `mkIf cfg.enable`.
3. Import the module from the host that should run it.
4. Enable it in that host's `fleet.*` config.
5. Run `nix flake check`, build the host, and dry-activate before switching.

For `media-vm` changes touching the media stack, SMB mounts, SOPS secrets, or
Restic, deploy and then run:

```sh
scripts/test-media-backup.sh
```

Keep README changes and `/etc/fleet/media-vm.md` recovery notes aligned when
backup or restore behavior changes.

## Safety Notes

- `hosts.nix` declares the `media-vm` disk as `/dev/sda`; any installer or
  partitioning command against that disk is destructive.
- Keep secret values encrypted before committing.
- Do not paste decrypted secrets into commits, issues, chat, logs, or shell history.
- The base firewall opens SSH and service modules open their own required ports.
- Add Traefik names to Technitium, local DNS, or `/etc/hosts` before expecting
  `*.home.arpa` routes to resolve.
