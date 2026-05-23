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

  mediaDirs = [
    mediaRoot
    cfg.libraries.audiobooks
    cfg.libraries.books
    cfg.libraries.calibre
    cfg.libraries.comics
    cfg.libraries.kidsMovies
    cfg.libraries.kidsTv
    cfg.libraries.movies
    cfg.libraries.newMovies
    cfg.libraries.pdfs
    cfg.libraries.podcasts
    cfg.libraries.tv
    cfg.downloads.incomplete
    cfg.downloads.root
    cfg.downloads.torrents
    cfg.downloads.usenet
  ];

  sabnzbdConfig = pkgs.writeText "sabnzbd.ini" ''
    [misc]
    host = 0.0.0.0
    port = ${toString cfg.ports.sabnzbd}
    download_dir = ${cfg.downloads.incomplete}
    complete_dir = ${cfg.downloads.usenet}
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
          "x-systemd.automount"
          "x-systemd.idle-timeout=60"
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
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # USERS, GROUPS, AND DIRECTORIES
    # --------------------------------------------------------------------------

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

    systemd.tmpfiles.rules =
      (map (path: "d '${path}' 0770 root media - -") appsdataDirs)
      ++ (map (path: "d '${path}' 0775 root media - -") mediaDirs)
      ++ [
        "d '${cfg.smb.backupMount}' 0750 root root - -"
        "d '${cfg.backup.repository}' 0750 root root - -"
      ];

    # --------------------------------------------------------------------------
    # SMB MOUNTS
    # --------------------------------------------------------------------------

    fileSystems.${mediaRoot} = {
      device = cfg.smb.mediaDevice;
      fsType = "cifs";
      options = cfg.smb.mountOptions ++ [
        "credentials=${smbCredentialsFile}"
        "dir_mode=0775"
        "file_mode=0664"
        "forcegid"
        "forceuid"
        "gid=media"
        "uid=media"
      ];
    };

    fileSystems.${cfg.smb.backupMount} = {
      device = cfg.smb.backupDevice;
      fsType = "cifs";
      options = cfg.smb.mountOptions ++ [
        "credentials=${smbCredentialsFile}"
        "dir_mode=0750"
        "file_mode=0640"
        "forcegid"
        "gid=media"
      ];
    };

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
      serverConfig = {
        LegalNotice.Accepted = true;
        Preferences = {
          Downloads = {
            SavePath = cfg.downloads.torrents;
            TempPath = cfg.downloads.incomplete;
            TempPathEnabled = true;
          };
          WebUI = {
            Address = "*";
            Port = cfg.ports.qbittorrent;
          };
        };
      };
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
      radarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      radarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      sonarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      sonarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      bazarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      bazarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      qbittorrent.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      qbittorrent.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
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

        restic snapshots >/dev/null 2>&1 || restic init
        restic backup '${cfg.backup.source}' \
          --one-file-system \
          --exclude-caches \
          --exclude '${appdata}/jellyfin/cache'
        restic forget \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --prune
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

      Restore /srv/appsdata after reinstalling this NixOS host, then redeploy.
      Media files under /mnt/media are mounted from SMB and are not included in
      appsdata-backup.service.

      Jellyfin kids access is configured inside Jellyfin after first setup:
      create a non-admin user named kids, grant only the Kids Movies and Kids TV
      Shows libraries, disable deletion and downloads, then optionally use
      parental controls or a kids-approved tag for an extra guardrail.

      First-run setup is available at http://10.2.20.113:8096/web/index.html#!/wizardstart.html.
      Complete it in a browser before connecting native Jellyfin clients.
    '';
  };
}
