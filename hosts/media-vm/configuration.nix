{
  config,
  lib,
  pkgs,
  ...
}:

let
  hosts = import ../../hosts.nix;
  host = hosts.media-vm;
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
    ../../modules/media/stack.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "media-vm";
  networking.domain = host.domain;
  users.motd = "media-vm: Jellyfin, ARR stack, downloads, and appdata backups";

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
      qbittorrent-webui-password.restartUnits = [ "qbittorrent.service" ];
      qbittorrent-webui-username.restartUnits = [ "qbittorrent.service" ];
      restic-password = { };
      smb-credentials = { };
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "media"
      "systemd-journal"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.media.stack = {
    enable = true;
    jellyfin.publishedServerUrl = "http://${host.ip}:8096";
    secrets.enable = secretsEnabled;
    smb = {
      backupDevice = "//nas.home.arpa/backups";
      mediaDevice = "//nas.home.arpa/media";
    };
  };

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

  # ============================================================================
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = host.vm.disk;
  boot.loader.grub.useOSProber = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  time.timeZone = host.timezone;
  system.stateVersion = "25.11";
}
