{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  cfg = config.fleet.media.stack;
  appdata = cfg.appdataRoot;
  mediaRoot = cfg.mediaRoot;
  smbCredentialsFile =
    if cfg.secrets.enable then
      config.sops.secrets.smb-credentials.path
    else
      "/run/secrets/smb-credentials";
  resticPasswordFile =
    if cfg.secrets.enable then
      config.sops.secrets.restic-password.path
    else
      "/run/secrets/restic-password";
  qbittorrentWebuiPasswordFile =
    if cfg.secrets.enable then
      config.sops.secrets.qbittorrent-webui-password.path
    else
      "/run/secrets/qbittorrent-webui-password";
  qbittorrentWebuiUsernameFile =
    if cfg.secrets.enable then
      config.sops.secrets.qbittorrent-webui-username.path
    else
      "/run/secrets/qbittorrent-webui-username";
  systemdMountOptions = filter (
    option:
    option != "_netdev"
    && option != "noauto"
    && option != "nofail"
    && !(hasPrefix "x-systemd." option)
  ) cfg.smb.mountOptions;

  appsdataDirs = [
    "${appdata}"
    "${appdata}/bazarr"
    "${appdata}/flaresolverr"
    "${appdata}/jellyfin"
    "${appdata}/jellyfin/cache"
    "${appdata}/jellyseerr"
    "${appdata}/monitoring"
    "${appdata}/prowlarr"
    "${appdata}/qbittorrent"
    "${appdata}/radarr"
    "${appdata}/sabnzbd"
    "${appdata}/sonarr"
  ];

  sabnzbdConfig = pkgs.writeText "sabnzbd.ini" ''
    [misc]
    host = 0.0.0.0
    port = ${toString cfg.ports.sabnzbd}
    download_dir = ${cfg.downloads.incomplete}
    complete_dir = ${cfg.downloads.usenet}
  '';

  qbittorrentConfigScript = pkgs.writeShellScript "configure-qbittorrent" ''
    set -euo pipefail

    exec ${pkgs.python3}/bin/python3 - <<'PY'
    import base64
    import hashlib
    import os
    import pathlib
    import pwd
    import grp
    import tempfile

    config_dir = pathlib.Path(${builtins.toJSON "${appdata}/qbittorrent/qBittorrent/config"})
    config_file = config_dir / "qBittorrent.conf"
    username_file = pathlib.Path(${builtins.toJSON qbittorrentWebuiUsernameFile})
    password_file = pathlib.Path(${builtins.toJSON qbittorrentWebuiPasswordFile})

    def read_secret(path, name):
        value = path.read_text(encoding="utf-8").rstrip("\n")
        if not value:
            raise RuntimeError(f"qBittorrent WebUI {name} secret is empty: {path}")
        if "\n" in value or "\r" in value:
            raise RuntimeError(f"qBittorrent WebUI {name} secret must be a single line: {path}")
        return value

    username = read_secret(username_file, "username")
    password = read_secret(password_file, "password")

    salt = os.urandom(16)
    password_hash = hashlib.pbkdf2_hmac("sha512", password.encode("utf-8"), salt, 100000)
    encoded_salt = base64.b64encode(salt).decode("ascii")
    encoded_hash = base64.b64encode(password_hash).decode("ascii")

    content = f"""[LegalNotice]
    Accepted=true

    [Preferences]
    Downloads\\SavePath=${cfg.downloads.torrents}
    Downloads\\TempPath=${cfg.downloads.incomplete}
    Downloads\\TempPathEnabled=true
    WebUI\\Address=*
    WebUI\\Password_PBKDF2="@ByteArray({encoded_salt}:{encoded_hash})"
    WebUI\\Port=${toString cfg.ports.qbittorrent}
    WebUI\\Username={username}
    """

    config_dir.mkdir(parents=True, exist_ok=True)
    uid = pwd.getpwnam("qbittorrent").pw_uid
    gid = grp.getgrnam("media").gr_gid

    fd, tmp_name = tempfile.mkstemp(prefix=".qBittorrent.conf.", dir=config_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            tmp.write(content)
        os.chown(tmp_name, uid, gid)
        os.chmod(tmp_name, 0o600)
        os.replace(tmp_name, config_file)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
    PY
  '';
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.stack = {
    enable = mkEnableOption "media-vm Jellyfin and ARR stack";

    appdataRoot = mkOption {
      type = types.path;
      default = "/srv/appsdata";
      description = "Single restore-critical application data root.";
    };

    mediaRoot = mkOption {
      type = types.path;
      default = "/mnt/media";
      description = "Mounted media library root.";
    };

    secrets.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Use sops-nix secrets from secrets/secrets.yaml.";
    };

    libraries = mkOption {
      type = types.attrsOf types.path;
      default = {
        audiobooks = "/mnt/media/Audiobooks";
        books = "/mnt/media/Books";
        calibre = "/mnt/media/Books";
        comics = "/mnt/media/Comics";
        kidsMovies = "/mnt/media/KidsMedia/KidsMovies";
        kidsTv = "/mnt/media/KidsMedia/KidsTVshows";
        movies = "/mnt/media/MOVIES";
        newMovies = "/mnt/media/NewMovies";
        pdfs = "/mnt/media/PDFs";
        podcasts = "/mnt/media/Podcasts";
        tv = "/mnt/media/TVshows";
      };
      description = "Media library paths.";
    };

    downloads = mkOption {
      type = types.attrsOf types.path;
      default = {
        incomplete = "/mnt/media/downloads/in-progress";
        root = "/mnt/media/downloads";
        torrents = "/mnt/media/downloads/downloads";
        usenet = "/mnt/media/downloads/downloads";
      };
      description = "Download paths for torrent and Usenet clients.";
    };

    ports = mkOption {
      type = types.attrsOf types.port;
      default = {
        bazarr = 6767;
        jellyfin = 8096;
        jellyseerr = 5055;
        prowlarr = 9696;
        qbittorrent = 8080;
        radarr = 7878;
        sabnzbd = 8085;
        sonarr = 8989;
      };
      description = "Web UI ports for exposed media services.";
    };

    jellyfin.publishedServerUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional URL Jellyfin advertises to clients during auto-discovery.";
    };

    smb = {
      mediaDevice = mkOption {
        type = types.str;
        default = "//nas.home.arpa/media";
        description = "SMB device for the media share.";
      };

      backupDevice = mkOption {
        type = types.str;
        default = "//nas.home.arpa/backups";
        description = "SMB device for the backup share.";
      };

      backupMount = mkOption {
        type = types.path;
        default = "/mnt/backups";
        description = "Backup SMB mount point.";
      };

      mountOptions = mkOption {
        type = types.listOf types.str;
        default = [
          "vers=3.0"
          "noauto"
          "nofail"
          "x-systemd.automount"
          "x-systemd.after=network-online.target"
          "x-systemd.idle-timeout=60"
          "x-systemd.mount-timeout=30s"
          "x-systemd.requires=network-online.target"
          "_netdev"
        ];
        description = "Systemd-aware CIFS mount options.";
      };
    };

    backup = {
      repository = mkOption {
        type = types.path;
        default = "/mnt/backups/restic/appdata/media-stack-vm";
        description = "Restic repository path.";
      };

      source = mkOption {
        type = types.path;
        default = "/srv/appsdata";
        description = "Path backed up by appsdata-backup.service.";
      };

      restoreCheckTarget = mkOption {
        type = types.path;
        default = "/var/tmp/appsdata-restore-check";
        description = "Temporary target used by appsdata-restore-check.service.";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # USERS, GROUPS, AND DIRECTORIES
    # --------------------------------------------------------------------------

    boot.supportedFilesystems.cifs = true;

    users.groups.media = { };

    users.users.media = {
      isSystemUser = true;
      group = "media";
      home = appdata;
    };

    users.users.jellyseerr = {
      isSystemUser = true;
      group = "media";
      home = "${appdata}/jellyseerr";
    };

    systemd.tmpfiles.rules = map (path: "d '${path}' 0770 root media - -") appsdataDirs;

    # --------------------------------------------------------------------------
    # SMB MOUNTS
    # --------------------------------------------------------------------------

    systemd.automounts = [
      {
        where = toString cfg.smb.backupMount;
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "60s";
      }
      {
        where = toString mediaRoot;
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "60s";
      }
    ];

    systemd.mounts = [
      {
        description = "Backup SMB share";
        what = cfg.smb.backupDevice;
        where = toString cfg.smb.backupMount;
        type = "cifs";
        options = concatStringsSep "," (
          systemdMountOptions
          ++ [
            "credentials=${smbCredentialsFile}"
            "dir_mode=0750"
            "file_mode=0640"
            "forcegid"
            "gid=media"
          ]
        );
        after = [ "network-online.target" ];
        before = [ "umount.target" ];
        conflicts = [ "umount.target" ];
        requires = [ "network-online.target" ];
        unitConfig.DefaultDependencies = false;
        mountConfig.TimeoutSec = "30s";
      }
      {
        description = "Media SMB share";
        what = cfg.smb.mediaDevice;
        where = toString mediaRoot;
        type = "cifs";
        options = concatStringsSep "," (
          systemdMountOptions
          ++ [
            "credentials=${smbCredentialsFile}"
            "dir_mode=0775"
            "file_mode=0664"
            "forcegid"
            "forceuid"
            "gid=media"
            "uid=media"
          ]
        );
        after = [ "network-online.target" ];
        before = [ "umount.target" ];
        conflicts = [ "umount.target" ];
        requires = [ "network-online.target" ];
        unitConfig.DefaultDependencies = false;
        mountConfig.TimeoutSec = "30s";
      }
    ];

    # --------------------------------------------------------------------------
    # MEDIA SERVICES
    # --------------------------------------------------------------------------

    services.jellyfin = {
      enable = true;
      openFirewall = true;
      user = "jellyfin";
      group = "media";
      dataDir = "${appdata}/jellyfin";
      configDir = "${appdata}/jellyfin/config";
      cacheDir = "${appdata}/jellyfin/cache";
      logDir = "${appdata}/jellyfin/log";
    };

    services.radarr = {
      enable = true;
      user = "radarr";
      group = "media";
      dataDir = "${appdata}/radarr";
      settings.server.port = cfg.ports.radarr;
    };

    services.sonarr = {
      enable = true;
      user = "sonarr";
      group = "media";
      dataDir = "${appdata}/sonarr";
      settings.server.port = cfg.ports.sonarr;
    };

    services.prowlarr = {
      enable = true;
      dataDir = "${appdata}/prowlarr";
      settings.server.port = cfg.ports.prowlarr;
    };

    services.bazarr = {
      enable = true;
      user = "bazarr";
      group = "media";
      dataDir = "${appdata}/bazarr";
      listenPort = cfg.ports.bazarr;
    };

    services.qbittorrent = {
      enable = true;
      user = "qbittorrent";
      group = "media";
      profileDir = "${appdata}/qbittorrent";
      webuiPort = cfg.ports.qbittorrent;
    };

    services.sabnzbd = {
      enable = true;
      user = "sabnzbd";
      group = "media";
      configFile = "${appdata}/sabnzbd/sabnzbd.ini";
    };

    services.jellyseerr = {
      enable = true;
      port = cfg.ports.jellyseerr;
      configDir = "${appdata}/jellyseerr";
    };

    services.flaresolverr = {
      enable = true;
      port = 8191;
    };

    systemd.services = {
      jellyfin.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      jellyfin.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      jellyfin.environment = mkIf (cfg.jellyfin.publishedServerUrl != null) {
        JELLYFIN_PublishedServerUrl = cfg.jellyfin.publishedServerUrl;
      };
      radarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      radarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      sonarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      sonarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      prowlarr.requires = [ "${utils.escapeSystemdPath "/var/lib/private/prowlarr"}.mount" ];
      prowlarr.after = [ "${utils.escapeSystemdPath "/var/lib/private/prowlarr"}.mount" ];
      bazarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      bazarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      qbittorrent.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      qbittorrent.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      qbittorrent.serviceConfig.ExecStartPre = [ "+${qbittorrentConfigScript}" ];
      qbittorrent.serviceConfig.UMask = "0077";
      sabnzbd.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      sabnzbd.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];

      sabnzbd = {
        preStart = ''
          if [ ! -f '${appdata}/sabnzbd/sabnzbd.ini' ]; then
            install -m 0640 ${sabnzbdConfig} '${appdata}/sabnzbd/sabnzbd.ini'
          fi
        '';
        serviceConfig.StateDirectory = mkForce "";
      };

      jellyseerr.serviceConfig = {
        DynamicUser = mkForce false;
        Group = "media";
        ReadWritePaths = [ "${appdata}/jellyseerr" ];
        StateDirectory = mkForce "";
        User = "jellyseerr";
      };
    };

    # --------------------------------------------------------------------------
    # BACKUPS
    # --------------------------------------------------------------------------

    environment.systemPackages = [ pkgs.restic ];

    systemd.services.appsdata-backup = {
      description = "Back up /srv/appsdata with restic";
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-appsdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run backup'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-appsdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run backup"
          exit 1
        fi

        mkdir -p "$RESTIC_REPOSITORY"
        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          restic init
        else
          restic snapshots \
            --host media-vm \
            --path '${cfg.backup.source}' \
            --tag appsdata \
            --latest 1 \
            --retry-lock 30m \
            >/dev/null
        fi

        restic backup '${cfg.backup.source}' \
          --host media-vm \
          --one-file-system \
          --exclude-caches \
          --exclude '${appdata}/jellyfin/cache' \
          --retry-lock 30m \
          --tag appsdata
        restic forget \
          --host media-vm \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --path '${cfg.backup.source}' \
          --prune \
          --retry-lock 30m \
          --tag appsdata
      '';
    };

    systemd.services.appsdata-restore-check = {
      description = "Verify /srv/appsdata can be restored from restic";
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-appsdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run restore check'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-appsdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run restore check"
          exit 1
        fi

        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          echo "$RESTIC_REPOSITORY is not an initialized restic repository"
          exit 1
        fi

        restore_parent='${cfg.backup.restoreCheckTarget}'
        case "$restore_parent" in
          /tmp/*|/var/tmp/*) ;;
          *)
            echo "restore check target must be under /tmp or /var/tmp: $restore_parent"
            exit 1
            ;;
        esac

        rm -rf -- "$restore_parent"
        install -d -m 0700 -o root -g root "$restore_parent"
        restore_root="$(mktemp -d "$restore_parent/run.XXXXXX")"
        cleanup() {
          rm -rf -- "$restore_root"
        }
        trap cleanup EXIT

        restic check --retry-lock 30m
        restic restore latest \
          --host media-vm \
          --path '${cfg.backup.source}' \
          --tag appsdata \
          --target "$restore_root" \
          --verify \
          --retry-lock 30m

        restored_source="$restore_root${cfg.backup.source}"
        if [ ! -d "$restored_source" ]; then
          echo "restore completed but $restored_source is missing"
          exit 1
        fi

        first_entry="$(find "$restored_source" -mindepth 1 -maxdepth 1 -print -quit)"
        if [ -z "$first_entry" ]; then
          echo "restore completed but $restored_source is empty"
          exit 1
        fi
      '';
    };

    systemd.timers.appsdata-backup = {
      description = "Daily /srv/appsdata restic backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        Unit = "appsdata-backup.service";
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [
      cfg.ports.bazarr
      cfg.ports.jellyfin
      cfg.ports.jellyseerr
      cfg.ports.prowlarr
      cfg.ports.qbittorrent
      cfg.ports.radarr
      cfg.ports.sabnzbd
      cfg.ports.sonarr
    ];

    # --------------------------------------------------------------------------
    # RECOVERY NOTES ON THE HOST
    # --------------------------------------------------------------------------

    environment.etc."fleet/media-vm.md".text = ''
      media-vm restore model
      ======================

      Restore /srv/appsdata after reinstalling this NixOS host, before first
      use of Jellyfin, ARR apps, qBittorrent, SABnzbd, or Jellyseerr. The first
      activation creates /run/secrets/restic-password, /mnt/backups, Restic,
      users/groups, and service units needed for restore.

      Media files under /mnt/media are mounted from SMB and are not included in
      appsdata-backup.service.

      Backup repository:
        /mnt/backups/restic/appdata/media-stack-vm

      Password file:
        /run/secrets/restic-password

      Non-destructive validation:
        mount /mnt/backups
        systemctl start appsdata-backup.service
        systemctl start appsdata-restore-check.service
        systemctl status appsdata-backup.service appsdata-restore-check.service

      Restore test target:
        /var/tmp/appsdata-restore-check

      Bootstrap restore outline:
        1. Deploy media-vm once.
        2. Before opening app web UIs, run this from the repo development shell:
             scripts/restore-media-appdata.sh
        3. The script stops media services, mounts /mnt/backups, checks for
           media-vm/appsdata snapshots, restores the latest snapshot if found,
           reapplies tmpfiles, and restarts media services.
        4. If no matching snapshot exists, the script starts media services and
           appsdata-backup.timer, then continues as a fresh system.

      Full restore outline:
        1. Stop appsdata-backup.timer and media services.
        2. Mount /mnt/backups.
        3. Restore the latest media-vm/appsdata snapshot to / with restic --verify.
        4. Run systemd-tmpfiles --create.
        5. Start media services, appsdata-backup.timer, and appsdata-restore-check.service.

      Jellyfin kids access is configured inside Jellyfin after first setup:
      create a non-admin user named kids, grant only the Kids Movies and Kids TV
      Shows libraries, disable deletion and downloads, then optionally use
      parental controls or a kids-approved tag for an extra guardrail.

      First-run setup is available at http://10.2.20.113:8096/web/index.html#!/wizardstart.html.
      Complete it in a browser before connecting native Jellyfin clients.
    '';
  };
}
