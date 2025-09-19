{ config, pkgs, ... }:

let
  hosts = import ../../hosts.nix;
in

{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/monitoring/prometheus.nix
    ../../modules/monitoring/grafana.nix
    ../../modules/dev/jenkins.nix
    ../../modules/networking/reverse-proxy.nix
    ../../modules/security/self-signed-ca.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "alpha";
  users.motd = "Welcome brave warrior to the ALPHA server";

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.dev.jenkins.enable = true;

  fleet.monitoring.prometheus = {
    enable = true;
    nodeExporterTargets = [
      "${hosts.alpha.ip}:9100"
      "${hosts.bravo.ip}:9100"
      "${hosts.charlie.ip}:9100"
    ];
  };

  fleet.monitoring.grafana = {
    enable = true;
    domain = hosts.alpha.ip;
    prometheusUrl = "http://localhost:9090";
  };

  # --------------------------------------------------------------------------
  # TLS CERTIFICATES
  # --------------------------------------------------------------------------

  fleet.security.selfSignedCA = {
    enable = true;
    caName = "Fleet Internal CA";
    domains = [
      "jenkins.local"
      "grafana.local"
      "prometheus.local"
      "git.local"
      "rss.local"
    ];
  };

  # --------------------------------------------------------------------------
  # REVERSE PROXY
  # --------------------------------------------------------------------------

  fleet.networking.reverseProxy = {
    enable = true;
    enableTLS = true;
    routes = {
      "jenkins.local" = {
        target = hosts.alpha.ip;
        port = 8080;
        description = "Jenkins CI/CD";
      };
      "grafana.local" = {
        target = hosts.alpha.ip;
        port = 3000;
        description = "Grafana monitoring dashboard";
      };
      "prometheus.local" = {
        target = hosts.alpha.ip;
        port = 9090;
        description = "Prometheus metrics";
      };
      "git.local" = {
        target = hosts.bravo.ip;
        port = 3000;
        description = "Gitea repository hosting";
        extraConfig = ''
          client_max_body_size 500M;
          proxy_read_timeout 300;
          proxy_send_timeout 300;
        '';
      };
      "rss.local" = {
        target = hosts.charlie.ip;
        port = 8080;
        description = "FreshRSS feed aggregator";
      };
    };
  };

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking.firewall.allowedTCPPorts = [ ];

  # ============================================================================
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  system.stateVersion = "25.05";
}
