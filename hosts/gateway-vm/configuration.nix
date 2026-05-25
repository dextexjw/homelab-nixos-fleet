{
  config,
  lib,
  ...
}:

let
  hosts = import ../../hosts.nix;
  host = hosts.gateway-vm;
  domain = host.domain;
  secretsFile = ../../secrets/secrets.yaml;
  secretsEnabled = builtins.pathExists secretsFile;
in

{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/gateway/netbird.nix
    ../../modules/gateway/netbootxyz.nix
    ../../modules/gateway/state-backup.nix
    ../../modules/gateway/tailscale.nix
    ../../modules/gateway/technitium.nix
    ../../modules/gateway/traefik.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "gateway-vm";
  networking.domain = host.domain;
  users.motd = "gateway-vm: Traefik ingress, Technitium DNS, netboot.xyz, NetBird, and Tailscale";

  # ============================================================================
  # SECRETS
  # ============================================================================

  sops = lib.mkIf secretsEnabled {
    defaultSopsFile = secretsFile;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      admin-password-hash = {
        neededForUsers = true;
      };
      restic-password = {
        restartUnits = [ "gateway-state-backup.service" ];
      };
      smb-credentials = { };
      technitium-admin-password = {
        restartUnits = [ "technitium-dns-configure.service" ];
      };
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "systemd-journal"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.gateway.netbird = {
    enable = true;
  };

  fleet.gateway.netbootxyz = {
    enable = true;
    bindAddress = host.ip;
  };

  fleet.gateway.stateBackup = {
    enable = secretsEnabled;
    credentialsFile = config.sops.secrets.smb-credentials.path;
    passwordFile = config.sops.secrets.restic-password.path;
  };

  fleet.gateway.tailscale = {
    enable = true;
  };

  fleet.gateway.technitium = {
    adminPasswordFile = config.sops.secrets.technitium-admin-password.path;
    enable = true;
    serverDomain = host.fqdn;
    tlsCertificateDomain = "technitium.${domain}";
    tlsSubjectAltNames = [
      "DNS:technitium.${domain}"
      "DNS:gateway-vm.${domain}"
      "IP:${host.ip}"
    ];
  };

  fleet.gateway.traefik = {
    dashboard.domain = "traefik.${domain}";
    domain = domain;
    enable = true;
    routes = {
      audiobookshelf = {
        description = "Audiobookshelf media library";
        host = "audiobookshelf.${domain}";
        url = "http://${hosts.media-vm.ip}:8000";
      };
      bazarr = {
        description = "Bazarr subtitle management";
        host = "bazarr.${domain}";
        url = "http://${hosts.media-vm.ip}:6767";
      };
      jellyfin = {
        description = "Jellyfin media server";
        host = "jellyfin.${domain}";
        url = "http://${hosts.media-vm.ip}:8096";
      };
      jellyseerr = {
        description = "Jellyseerr requests";
        host = "jellyseerr.${domain}";
        url = "http://${hosts.media-vm.ip}:5055";
      };
      kavita = {
        description = "Kavita library";
        host = "kavita.${domain}";
        url = "http://${hosts.media-vm.ip}:5000";
      };
      prowlarr = {
        description = "Prowlarr indexer management";
        host = "prowlarr.${domain}";
        url = "http://${hosts.media-vm.ip}:9696";
      };
      qbittorrent = {
        description = "qBittorrent downloads";
        host = "qbittorrent.${domain}";
        url = "http://${hosts.media-vm.ip}:8080";
      };
      radarr = {
        description = "Radarr movie management";
        host = "radarr.${domain}";
        url = "http://${hosts.media-vm.ip}:7878";
      };
      sabnzbd = {
        description = "SABnzbd downloads";
        host = "sabnzbd.${domain}";
        url = "http://${hosts.media-vm.ip}:8085";
      };
      sonarr = {
        description = "Sonarr TV management";
        host = "sonarr.${domain}";
        url = "http://${hosts.media-vm.ip}:8989";
      };
      technitium = {
        description = "Technitium DNS administration and DoH endpoint";
        host = "technitium.${domain}";
        url = "http://127.0.0.1:5380";
      };
    };
  };

  # common.nix enables node-exporter by default; gateway-vm intentionally does
  # not run monitoring services.
  fleet.monitoring.nodeExporter.enable = lib.mkForce false;

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking.networkmanager.enable = lib.mkForce false;
  networking.useDHCP = lib.mkForce false;
  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = [
        "en*"
        "eth*"
      ];
      networkConfig = {
        Address = "${host.ip}/24";
        DNS = host.nameservers;
        Domains = host.domain;
        Gateway = host.gateway;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ ];

  # ============================================================================
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = host.vm.disk;
  boot.loader.grub.useOSProber = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  environment.etc."fleet/gateway-vm.md".text = ''
    gateway-vm service model
    ========================

    gateway-vm is scoped to Traefik, Technitium, netboot.xyz, NetBird, and
    Tailscale. Prometheus, Grafana, Jenkins, nginx reverse proxy, and node
    exporter are intentionally not enabled on this host.

    Homelab domain:
      *.${domain}

    Declared services:
      Traefik: traefik.service, ports 80 and optional 443
      Technitium: technitium-dns-server.service, state /srv/appsdata/technitium-dns-server
      netboot.xyz: atftpd.service, TFTP root /srv/netbootxyz, boot file netboot.xyz.efi
      NetBird: netbird.service, state /srv/appsdata/netbird
      Tailscale: tailscaled.service, state /srv/appsdata/tailscale
      State backups: gateway-state-backup.timer, repository /mnt/backup/restic/appdata/gateway-vm

    Internal routes:
      http://traefik.${domain}
      http://technitium.${domain}
      http://jellyfin.${domain}
      http://audiobookshelf.${domain}
      http://kavita.${domain}
      http://sonarr.${domain}
      http://radarr.${domain}
      http://prowlarr.${domain}
      http://bazarr.${domain}
      http://qbittorrent.${domain}
      http://sabnzbd.${domain}
      http://jellyseerr.${domain}

    Network boot:
      Configure the LAN DHCP server to point option 66 at ${hosts.gateway-vm.ip}
      and option 67 at netboot.xyz.efi. gateway-vm only serves TFTP and does not
      take over DHCP for the subnet.

    Guarded deploy workflow:
      nix develop
      nix flake check
      colmena build --on gateway-vm
      colmena apply --on gateway-vm dry-activate
      colmena apply --on gateway-vm switch

    Post-deploy validation:
      systemctl is-active traefik.service
      systemctl is-active technitium-dns-server.service
      systemctl is-active atftpd.service
      systemctl is-active netbird.service
      systemctl is-active tailscaled.service
      systemctl is-active gateway-state-backup.timer
      ss -lntu

    Recovery notes:
      Restic backs up /srv/appsdata to /mnt/backup/restic/appdata/gateway-vm
      using /run/secrets/restic-password. Technitium, NetBird, and Tailscale
      keep upstream-compatible bind mounts from /srv/appsdata/<service_name>.

      Non-destructive validation:
        mount /mnt/backup
        systemctl start gateway-state-backup.service
        systemctl start gateway-state-restore-check.service
        systemctl status gateway-state-backup.service gateway-state-restore-check.service

      Restore outline:
        1. Deploy gateway-vm once to create users, secrets, mounts, and units.
        2. Stop Technitium, NetBird, and Tailscale before replacing state.
        3. Mount /mnt/backup.
        4. Choose a gateway-vm/appsdata snapshot ID.
        5. Restore the snapshot to / with restic --verify.
        6. Run systemd-tmpfiles --create.
        7. Restart technitium-dns-server.service, netbird.service, and tailscaled.service.

      Keep auth keys in encrypted secrets only; do not write them into Nix
      files, generated configs, recovery notes, logs, or chat.
  '';

  time.timeZone = host.timezone;
  system.stateVersion = "25.11";
}
