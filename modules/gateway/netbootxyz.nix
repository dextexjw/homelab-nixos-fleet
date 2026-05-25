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
    enable = mkEnableOption "netboot.xyz TFTP boot service";

    bindAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional address for atftpd to bind.";
      example = "10.2.20.112";
    };

    bootFile = mkOption {
      type = types.str;
      default = "netboot.xyz.efi";
      description = "Boot filename exposed from the TFTP root.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open UDP/69 for TFTP.";
    };

    tftpRoot = mkOption {
      type = types.path;
      default = "/srv/netbootxyz";
      description = "TFTP document root.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    services.atftpd = {
      enable = true;
      extraOptions = optional (cfg.bindAddress != null) "--bind-address ${cfg.bindAddress}";
      root = cfg.tftpRoot;
    };

    systemd.services.atftpd = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.tftpRoot} 0755 root root - -"
      "L+ ${cfg.tftpRoot}/${cfg.bootFile} - - - - ${pkgs.netbootxyz-efi}"
    ];

    networking.firewall.allowedUDPPorts = mkIf cfg.openFirewall [ 69 ];
  };
}
