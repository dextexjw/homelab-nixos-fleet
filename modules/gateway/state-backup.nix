{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.stateBackup;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.stateBackup = {
    enable = mkEnableOption "gateway-vm state backups";

    backupDevice = mkOption {
      type = types.str;
      default = "//nas.home.arpa/backups";
      description = "SMB share used for gateway state backups.";
    };

    credentialsFile = mkOption {
      type = types.path;
      description = "Runtime SMB credentials file.";
      example = "/run/secrets/smb-credentials";
    };

    mountPoint = mkOption {
      type = types.path;
      default = "/mnt/gateway-backups";
      description = "Mount point for gateway backup storage.";
    };

    passwordFile = mkOption {
      type = types.path;
      description = "Runtime Restic password file.";
      example = "/run/secrets/restic-password";
    };

    paths = mkOption {
      type = types.listOf types.path;
      default = [
        "/var/lib/netbird"
        "/var/lib/tailscale"
        "/var/lib/private/technitium-dns-server"
      ];
      description = "Gateway state paths included in Restic backups.";
    };

    repository = mkOption {
      type = types.str;
      default = "/mnt/gateway-backups/restic/gateway-vm/state";
      description = "Restic repository path for gateway state.";
    };

    retention = mkOption {
      type = types.str;
      default = "--keep-daily 14 --keep-weekly 8 --keep-monthly 6";
      description = "Restic forget/prune retention flags.";
    };

    restoreCheckTarget = mkOption {
      type = types.path;
      default = "/var/tmp/gateway-state-restore-check";
      description = "Non-destructive restore-check target.";
    };

    timerCalendar = mkOption {
      type = types.str;
      default = "daily";
      description = "systemd calendar for gateway state backups.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.restic ];

    fileSystems.${cfg.mountPoint} = {
      device = cfg.backupDevice;
      fsType = "cifs";
      options = [
        "credentials=${cfg.credentialsFile}"
        "dir_mode=0700"
        "file_mode=0600"
        "gid=0"
        "iocharset=utf8"
        "nofail"
        "noauto"
        "uid=0"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.restoreCheckTarget} 0700 root root - -"
    ];

    systemd.services.gateway-state-backup = {
      description = "Back up gateway-vm state";
      after = [ "${utils.escapeSystemdPath cfg.mountPoint}.mount" ];
      wants = [ "${utils.escapeSystemdPath cfg.mountPoint}.mount" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.util-linux
      ];
      script = ''
        set -euo pipefail

        mountpoint -q ${cfg.mountPoint} || mount ${cfg.mountPoint}
        mkdir -p "$(dirname "${cfg.repository}")"

        if ! restic --repo "${cfg.repository}" --password-file "${cfg.passwordFile}" snapshots >/dev/null 2>&1; then
          restic --repo "${cfg.repository}" --password-file "${cfg.passwordFile}" init
        fi

        restic --repo "${cfg.repository}" --password-file "${cfg.passwordFile}" backup \
          --host gateway-vm \
          --tag gateway-state \
          ${escapeShellArgs cfg.paths}

        restic --repo "${cfg.repository}" --password-file "${cfg.passwordFile}" forget \
          --host gateway-vm \
          --tag gateway-state \
          --prune \
          ${cfg.retention}
      '';
    };

    systemd.timers.gateway-state-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.timerCalendar;
        Persistent = true;
        Unit = "gateway-state-backup.service";
      };
    };

    systemd.services.gateway-state-restore-check = {
      description = "Validate gateway-vm Restic state restore";
      after = [ "${utils.escapeSystemdPath cfg.mountPoint}.mount" ];
      wants = [ "${utils.escapeSystemdPath cfg.mountPoint}.mount" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.util-linux
      ];
      script = ''
        set -euo pipefail

        mountpoint -q ${cfg.mountPoint} || mount ${cfg.mountPoint}
        rm -rf "${cfg.restoreCheckTarget:?}"/*
        restic --repo "${cfg.repository}" --password-file "${cfg.passwordFile}" restore latest \
          --host gateway-vm \
          --tag gateway-state \
          --target "${cfg.restoreCheckTarget}" \
          --verify
        test -d "${cfg.restoreCheckTarget}/var/lib/netbird"
        test -d "${cfg.restoreCheckTarget}/var/lib/tailscale"
        test -d "${cfg.restoreCheckTarget}/var/lib/private/technitium-dns-server"
      '';
    };
  };
}
