# NixOS Fleet Management

This is a starter template for a setup similar to how I manage my own home servers using NixOS + Colmena.

You can use this as a starting point for your own setup.

## Overview

Fleet is a NixOS homelab managed with a Nix flake and deployed with Colmena. The current focus is `media-vm`, a NixOS host for Jellyfin, the ARR stack, download clients, appdata backups, and supporting services.

The `modules/` directory contains reusable pieces for different services. Want to run Prometheus? Import the module and set `fleet.monitoring.prometheus.enable = true`. Same pattern for everything else.

All the servers import `hosts/common.nix` which sets up SSH keys, basic security, and monitoring. Individual servers add whatever services they need on top of that.

The reverse proxy on the gateway-vm server routes traffic to services running on different machines. Self-signed certificates handle TLS so you don't get browser warnings.

## Repository layout

- `flake.nix` defines inputs, the development shell, and the Colmena hive.
- `hosts.nix` is the inventory for host IPs, users, tags, and media-vm constants.
- `hosts/<name>/configuration.nix` contains per-host NixOS configuration.
- `hosts/<name>/hardware-configuration.nix` comes from the target host.
- `hosts/common.nix` provides shared defaults.
- `modules/` contains reusable service modules under the `fleet.*` namespace.
- `modules/media/stack.nix` defines the `media-vm` media stack.
- `secrets/secrets.yaml` is the real SOPS-encrypted secrets file.
- `secrets/example-secrets.yaml` documents the expected secrets shape.
- `scripts/` contains maintenance helpers, including `scripts/test-media-backup.sh` for repeatable `media-vm` backup and restore validation. The documented deployment workflow still uses direct Colmena commands from the development shell.

## Getting started

You need Nix installed on your machine first. If you don't have it, grab it from nixos.org or use the https://determinate.systems/ installer (has some QoL improvements).

If you use direnv (and you should), there's a `.envrc` file that will automatically load the development shell when you enter the directory. Otherwise run `nix develop` manually.

First thing you need is some servers running NixOS. Could be VMs, could be old laptops, whatever. Get them installed and grab their IP addresses.

Edit `hosts.nix` and put your servers in there. Change the IPs and usernames to match your setup. The tags are just for organizing things - you can deploy to all servers with a certain tag.

Each server gets its own directory under `hosts/`. Copy one of the existing ones and modify it. The `hardware-configuration.nix` file comes from running `nixos-generate-config` on the target machine (or just scp'ing it from /etc/nixos/hardware-configuration.nix from the target).

Once you have that sorted, run `nix develop` to get into the development shell, then use the Colmena commands below.

### Deployment record

- **media-vm deployed**: `media-vm` at `10.2.20.113` successfully deployed using:

```
nix develop
colmena apply --on media-vm switch
```

## Development shell

Enter the development shell before running Colmena, SOPS, or helper scripts:

```sh
nix develop
```

The shell includes Colmena plus tools used by this repo such as `sops`, `age`, and `restic`.

## General Colmena commands

Deploy everything:

```sh
colmena apply switch
```

Deploy one server:

```sh
colmena apply --on servername switch
```

Deploy servers with a tag:

```sh
colmena apply --on @web switch
```

Run commands on servers:

```sh
colmena exec --on servername -- systemctl status nginx
```

Build without deploying:

```sh
colmena build --on servername
```

Preview activation without switching state:

```sh
colmena apply --on servername dry-activate
```

For `media-vm`, use `colmena apply --on media-vm switch`.

## media-vm host values

These values are already represented in `hosts.nix` and `hosts/media-vm/configuration.nix`:

- Hostname: `media-vm`
- Domain: `home.arpa`
- FQDN: `media.home.arpa`
- IP address: `10.2.20.113`
- Gateway: `10.2.20.1`
- DNS servers: `10.2.20.1`, `1.1.1.1`
- Time zone: `America/New_York`
- System architecture: `x86_64-linux`
- Admin username: `smoke`
- Admin SSH public key: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIATd/kn93HeAqaT5e8uW68n/JoWBesQkyruVNLsG3NDc khalid`
- VM ID: `113`
- VM name: `media-vm`
- VM disk: `/dev/sda`
- VM RAM: `12 GB`
- VM CPU cores: `4`
- Media SMB device: `//nas.home.arpa/media`
- Media mount: `/mnt/media`
- Backup SMB device: `//nas.home.arpa/backups`
- Backup mount: `/mnt/backups`

## media-vm services

`media-vm` runs:

- Jellyfin
- Radarr
- Sonarr
- Prowlarr
- Bazarr
- qBittorrent
- SABnzbd
- Jellyseerr
- FlareSolverr
- Prometheus node exporter

## media-vm storage model

`/srv/appsdata` is the single folder to back up for media-stack application recovery. It holds Jellyfin, Radarr, Sonarr, Prowlarr, Bazarr, qBittorrent, SABnzbd, Jellyseerr, FlareSolverr placeholder state, and monitoring backup state.

Media files under `/mnt/media` are mounted from SMB and are not included in `appsdata-backup.service`. Back up the NAS media share separately if you want movie, TV, book, podcast, audiobook, comic, or PDF files protected.

Appdata paths:

- Jellyfin: `/srv/appsdata/jellyfin`
- Radarr: `/srv/appsdata/radarr`
- Sonarr: `/srv/appsdata/sonarr`
- Prowlarr: `/srv/appsdata/prowlarr`
- Bazarr: `/srv/appsdata/bazarr`
- qBittorrent: `/srv/appsdata/qbittorrent`
- SABnzbd: `/srv/appsdata/sabnzbd`
- Jellyseerr: `/srv/appsdata/jellyseerr`
- FlareSolverr: `/srv/appsdata/flaresolverr`
- Monitoring: `/srv/appsdata/monitoring`

Media paths:

- Movies library 1: `/mnt/media/MOVIES`
- Movies library 2 / new movies: `/mnt/media/NewMovies`
- TV library: `/mnt/media/TVshows`
- Kids movies: `/mnt/media/KidsMedia/KidsMovies`
- Kids TV shows: `/mnt/media/KidsMedia/KidsTVshows`
- Audiobooks: `/mnt/media/Audiobooks`
- Podcasts: `/mnt/media/Podcasts`
- Ebooks and Calibre library: `/mnt/media/Books`
- Comics: `/mnt/media/Comics`
- PDFs: `/mnt/media/PDFs`
- Downloads root: `/mnt/media/downloads`
- Completed torrent downloads: `/mnt/media/downloads/downloads`
- Completed Usenet downloads: `/mnt/media/downloads/downloads`
- Incomplete downloads: `/mnt/media/downloads/in-progress`

## media-vm first-run secrets

Put the real values in `secrets/secrets.yaml`, then encrypt it with SOPS before deploying:

- `admin-password-hash`
- `smb-credentials`
- `restic-password`
- `qbittorrent-webui-username`
- `qbittorrent-webui-password`

Use a long random value for `restic-password`; it is the encryption key for the Restic repository and must be preserved with the repository history. If the Restic repository already exists and the password changes, Restic cannot read old snapshots with the new password.

The committed `secrets/secrets.yaml` is an encrypted placeholder until you replace it with your real encrypted values. Keep it encrypted before committing.

Important: sops-nix decrypts secrets on `media-vm` using the key paths configured in `hosts/media-vm/configuration.nix`. The current host config uses `/etc/ssh/ssh_host_ed25519_key`, so `.sops.yaml` must include a recipient that the `media-vm` host can decrypt with before deployment. If `.sops.yaml` only contains your personal/admin SSH public key, you can edit secrets locally but the host will not be able to decrypt them during activation.

To capture the `media-vm` host public key after the VM exists:

```sh
ssh smoke@10.2.20.113 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
```

Add that `age1...` recipient to `.sops.yaml`, then rekey `secrets/secrets.yaml`.

Note: qBittorrent reads `qbittorrent-webui-username` and `qbittorrent-webui-password`
from SOPS during service startup. The password is hashed on `media-vm` into
qBittorrent's `WebUI\Password_PBKDF2` config format, so the plaintext value does
not enter the Nix store. Changing either secret restarts `qbittorrent.service`.

## SOPS secrets workflow

Always work from the development shell so `sops` and `age` are available:

```sh
nix develop
```

### Edit encrypted secrets

Use this for normal updates:

```sh
sops secrets/secrets.yaml
```

SOPS opens a temporary decrypted view in your editor. Save and exit; the file on disk remains encrypted.

### Create or re-encrypt secrets.yaml

If `secrets/secrets.yaml` is missing, start from the example:

```sh
cp secrets/example-secrets.yaml secrets/secrets.yaml
sops --encrypt --in-place secrets/secrets.yaml
```

If the file is plaintext and has no `sops:` metadata block, encrypt it in place:

```sh
sops --encrypt --in-place secrets/secrets.yaml
```

After encryption, secret values should look like `ENC[AES256_GCM,...]` and the file should contain a top-level `sops:` metadata block.

### Check decryption safely

To verify the file decrypts without printing secret values:

```sh
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

To view decrypted content locally:

```sh
sops --decrypt secrets/secrets.yaml
```

Do not paste decrypted output into commits, issues, chat, logs, or shell history.

### Repair a half-encrypted file

If `sops secrets/secrets.yaml` fails with an error like `sops metadata not found`, the file is probably plaintext. Encrypt it:

```sh
sops --encrypt --in-place secrets/secrets.yaml
```

If it fails with an error like `does not match sops' data format`, the file likely has plaintext values plus a stale `sops:` block. Fix it by removing the entire top-level `sops:` block from `secrets/secrets.yaml`, then re-encrypt:

```sh
sops --encrypt --in-place secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

### Rekey after host key changes

If the `media-vm` SSH host key or the `.sops.yaml` recipient changes, rekey the file:

```sh
sops updatekeys secrets/secrets.yaml
```

After rekeying, verify decryption still works locally:

```sh
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

## media-vm bootstrap flow

1. Enter the development shell:

```sh
nix develop
```

2. Fill and encrypt `secrets/secrets.yaml` for your local/admin key.

3. Validate the local config:

```sh
nix flake check
colmena build --on media-vm
```

4. Install NixOS on the VM using your preferred installer flow.

5. Confirm SSH for `smoke@10.2.20.113` works.

6. Capture the VM's configured SOPS public key:

```sh
ssh smoke@10.2.20.113 'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' | ssh-to-age
```

The command prints an `age1...` public recipient. This value is not a secret. If that exact recipient is already listed in `.sops.yaml`, no edit is needed. If it is missing, add it to the comma-separated `age:` recipient list in `.sops.yaml`.

After confirming the recipient is present, rekey and verify the secrets file:

```sh
sops updatekeys secrets/secrets.yaml
sops --decrypt secrets/secrets.yaml >/dev/null && echo ok
```

This recipient must be derived from `/etc/ssh/ssh_host_ed25519_key`, because that is the private key `media-vm` uses to decrypt SOPS secrets during activation. Do not copy or commit the private key itself.

7. Deploy `media-vm`:

```sh
colmena apply --on media-vm switch
```

8. Confirm the hostname settled:

```sh
ssh smoke@10.2.20.113 'hostnamectl --static; hostnamectl --transient'
```

The static hostname should be `media-vm`. If the transient hostname still shows the installer/bootstrap name, either reboot once or set it explicitly:

```sh
ssh smoke@10.2.20.113 'sudo hostnamectl --transient hostname media-vm'
```

9. Validate backup and restore:

```sh
scripts/test-media-backup.sh
```

## media-vm day-2 deploy flow

Enter the development shell first:

```sh
nix develop
```

Validate and build only `media-vm`:

```sh
nix flake check
colmena build --on media-vm
colmena apply --on media-vm dry-activate
```

Deploy only `media-vm`:

```sh
colmena apply --on media-vm switch
```

For changes touching the media stack, SMB mounts, SOPS secrets, or Restic, run the repeatable backup and restore validation after deployment:

```sh
scripts/test-media-backup.sh
```

Use the broader Colmena targets only when you mean to deploy more than one host:

```sh
colmena apply --on @media switch
colmena apply switch
```

## media-vm service status

```sh
colmena exec --on media-vm -- systemctl status jellyfin
colmena exec --on media-vm -- systemctl status radarr
colmena exec --on media-vm -- systemctl status sonarr
colmena exec --on media-vm -- systemctl status prowlarr
colmena exec --on media-vm -- systemctl status bazarr
colmena exec --on media-vm -- systemctl status qbittorrent
colmena exec --on media-vm -- systemctl status sabnzbd
colmena exec --on media-vm -- systemctl status jellyseerr
colmena exec --on media-vm -- systemctl status flaresolverr
colmena exec --on media-vm -- systemctl status prometheus-node-exporter
```

## media-vm web UIs

- Jellyfin: `http://10.2.20.113:8096`
- Radarr: `http://10.2.20.113:7878`
- Sonarr: `http://10.2.20.113:8989`
- Prowlarr: `http://10.2.20.113:9696`
- Bazarr: `http://10.2.20.113:6767`
- qBittorrent: `http://10.2.20.113:8080`
- SABnzbd: `http://10.2.20.113:8085`
- Jellyseerr: `http://10.2.20.113:5055`

FlareSolverr listens on port `8191` for internal app integration and is not opened in the firewall.

## Jellyfin kids access

Use one Jellyfin instance. After first Jellyfin setup, create a non-admin user named `kids`, grant only the Kids Movies and Kids TV Shows libraries, disable deletion, disable downloads unless wanted, and use parental controls or a `kids-approved` tag as a secondary control.

## media-vm SMB mount checks

On `media-vm`:

```sh
mount /mnt/backups
ls -la /mnt/backups
```

You can also test the media share:

```sh
mount /mnt/media
ls -la /mnt/media
```

## media-vm backups

Backups are handled by `appsdata-backup.service` and `appsdata-backup.timer`.

- Source: `/srv/appsdata`
- Repository: `/mnt/backups/restic/appdata/media-stack-vm`
- Password file: `/run/secrets/restic-password`
- Schedule: daily
- Retention: 7 daily, 4 weekly, 6 monthly snapshots
- Restic host: `media-vm`
- Restic tag: `appsdata`
- Restore validation unit: `appsdata-restore-check.service`

Run the repeatable post-deploy validation from the development shell:

```sh
scripts/test-media-backup.sh
```

The script mounts `/mnt/backups` if needed, starts `appsdata-backup.service`, starts the non-destructive restore check, verifies the backup timer is active, and lists the latest tagged snapshots.

If Restic reports `wrong password or no key found`, the repository was initialized with a different password than `/run/secrets/restic-password`. Do not delete that repository. Preserve it under a dated name, fix the SOPS `restic-password`, deploy, and let `appsdata-backup.service` initialize a clean repository at the documented path.

Run a manual backup on `media-vm`:

```sh
systemctl start appsdata-backup.service
```

Inspect backups on `media-vm`:

```sh
systemctl status appsdata-backup.timer
journalctl -u appsdata-backup.service
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host media-vm --path /srv/appsdata --tag appsdata
```

Run the non-destructive restore validation on `media-vm`:

```sh
systemctl start appsdata-restore-check.service
journalctl -u appsdata-restore-check.service
```

## Restore /srv/appsdata

This is the destructive full restore procedure. Use `appsdata-restore-check.service` for routine validation because it restores into `/var/tmp/appsdata-restore-check` and does not overwrite `/srv/appsdata`.

1. Stop the backup timer and media services:

```sh
systemctl stop appsdata-backup.timer
systemctl stop jellyfin radarr sonarr prowlarr bazarr qbittorrent sabnzbd jellyseerr flaresolverr
```

2. Mount the backup share:

```sh
mount /mnt/backups
```

3. Confirm the target snapshot exists:

```sh
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host media-vm --path /srv/appsdata --tag appsdata
```

4. Restore the latest tagged snapshot:

```sh
RESTIC_REPOSITORY=/mnt/backups/restic/appdata/media-stack-vm \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic restore latest \
    --host media-vm \
    --path /srv/appsdata \
    --tag appsdata \
    --target / \
    --verify
```

5. Reapply declared directories, restart services, and validate:

```sh
systemd-tmpfiles --create
systemctl start jellyfin radarr sonarr prowlarr bazarr qbittorrent sabnzbd jellyseerr flaresolverr
systemctl start appsdata-backup.timer
systemctl start appsdata-restore-check.service
```

## Roll back a NixOS deployment

From `media-vm`, choose the previous generation:

```sh
sudo nixos-rebuild switch --rollback
```

Or reboot and select an earlier generation in the bootloader menu. After rollback, check the affected services with `systemctl status`.

## Safety notes around destructive disk installs

The VM disk is configured as `/dev/sda` in `hosts.nix`. Treat any install or partitioning command against that disk as destructive. Confirm the target VM ID, disk path, and console before running installer commands, and never run disk setup commands from this repository against a machine that has data you intend to keep.

## Adding services

Look at the existing modules to see how they work. Most follow the same pattern: define some options, implement the service when enabled. Import the module in your server config and enable it.

The fleet namespace keeps things organized. Everything lives under `fleet.category.service` like `fleet.monitoring.grafana` or `fleet.dev.gitea`.

As mentioned in the video, AI can do wonders for this.

## Notes

Make sure your SSH key is in `hosts/common.nix` or you won't be able to deploy.

If services aren't accessible, check the firewall settings. The base config opens SSH, and individual enabled service modules open only their required ports.

As a quick hack, add the reverse proxy domains to your `/etc/hosts` file so they resolve properly. But better to set up proper DNS.

This setup assumes you're semi-comfortable with NixOS. If you're new to NixOS and flakes, check out the book: https://nixos-and-flakes.thiscute.world/

The monitoring stack will start collecting metrics immediately. Grafana runs on port 3000 of your gateway-vm server (or whatever you call your main one).

## Resources

- Check out [VimJoyer](https://www.youtube.com/@vimjoyer) for all of the Nix videos
- [NixOS + Flakes book](https://nixos-and-flakes.thiscute.world/)
- [Colmena](https://github.com/zhaofengli/colmena)
