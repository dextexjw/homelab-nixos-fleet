{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.netbootxyz;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.netbootxyz = {
    enable = mkEnableOption "netboot.xyz network boot service";

    assetBindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address used for the local netboot.xyz asset server listener.";
      example = "127.0.0.1";
    };

    assetPort = mkOption {
      type = types.port;
      default = 8083;
      description = "Host port mapped to the netboot.xyz container asset server.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/netbootxyz/netbootxyz@sha256:942dfb60d11846b657a54dd36f1addf636b7736f38009223ce328ebc37f54d39";
      description = "Pinned netboot.xyz OCI image reference.";
    };

    menuVersion = mkOption {
      type = types.str;
      default = "2.0.88";
      description = "netboot.xyz menu version used by the container.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open UDP/69 for TFTP.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/srv/appsdata/netbootxyz";
      description = "Persistent netboot.xyz state directory.";
    };

    tftpBindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address used for the netboot.xyz TFTP listener.";
      example = "10.2.20.112";
    };

    tftpPort = mkOption {
      type = types.port;
      default = 69;
      description = "Host UDP port mapped to the netboot.xyz TFTP service.";
    };

    webUiBindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address used for the netboot.xyz web UI listener.";
      example = "127.0.0.1";
    };

    webUiPort = mkOption {
      type = types.port;
      default = 3001;
      description = "Host port mapped to the netboot.xyz web configuration UI.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.atftp ];

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.netbootxyz = {
      image = cfg.image;
      pull = "missing";

      environment = {
        MENU_VERSION = cfg.menuVersion;
        NGINX_PORT = "80";
        TFTPD_OPTS = "--tftp-single-port";
        WEB_APP_PORT = "3000";
      };

      ports = [
        "${cfg.tftpBindAddress}:${toString cfg.tftpPort}:69/udp"
        "${cfg.webUiBindAddress}:${toString cfg.webUiPort}:3000/tcp"
        "${cfg.assetBindAddress}:${toString cfg.assetPort}:80/tcp"
      ];

      volumes = [
        "${cfg.stateDir}/config:/config"
        "${cfg.stateDir}/assets:/assets"
      ];
    };

    systemd.services.podman-netbootxyz = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root - -"
      "d ${cfg.stateDir}/assets 0755 root root - -"
      "d ${cfg.stateDir}/config 0755 root root - -"
    ];

    networking.firewall.allowedUDPPorts = mkIf cfg.openFirewall [ cfg.tftpPort ];
  };
}
