{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.technitium;
  adminPasswordFileArg =
    if cfg.adminPasswordFile == null then
      "''"
    else
      escapeShellArg cfg.adminPasswordFile;
  bool = value: if value then "true" else "false";
  certificatePath = "/var/lib/technitium-dns-server/tls/${cfg.tlsCertificateDomain}.pfx";
  sanList = concatStringsSep "," cfg.tlsSubjectAltNames;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.technitium = {
    enable = mkEnableOption "Technitium DNS Server";

    adminPasswordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime secret file containing the Technitium admin password.";
    };

    configureEncryptedDns = mkOption {
      type = types.bool;
      default = true;
      description = "Configure DNS-over-TLS and DNS-over-HTTPS through the Technitium API.";
    };

    dnsOverTlsPort = mkOption {
      type = types.port;
      default = 853;
      description = "DNS-over-TLS port to allow through the firewall.";
    };

    dnsPort = mkOption {
      type = types.port;
      default = 53;
      description = "Recursive DNS port.";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 53443;
      description = "Technitium HTTPS and DNS-over-HTTPS port.";
    };

    serverDomain = mkOption {
      type = types.str;
      default = config.networking.fqdnOrHostName;
      description = "Primary domain name Technitium uses to identify this DNS server.";
    };

    tlsCertificateDomain = mkOption {
      type = types.str;
      default = config.networking.fqdnOrHostName;
      description = "Domain name used for the generated local TLS certificate.";
    };

    tlsSubjectAltNames = mkOption {
      type = types.listOf types.str;
      default = [ "DNS:${cfg.tlsCertificateDomain}" ];
      description = "Subject alternative names for the generated local TLS certificate.";
    };

    webPort = mkOption {
      type = types.port;
      default = 5380;
      description = "Technitium HTTP administration port.";
    };

    webServiceLocalAddresses = mkOption {
      type = types.str;
      default = "127.0.0.1,::1";
      description = "Comma-separated local addresses for the Technitium web console.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    services.technitium-dns-server = {
      enable = true;
      openFirewall = true;
      firewallTCPPorts = unique [
        cfg.dnsPort
        cfg.dnsOverTlsPort
        cfg.httpsPort
        cfg.webPort
      ];
      firewallUDPPorts = [ cfg.dnsPort ];
    };

    systemd.services.technitium-dns-server = {
      environment =
        {
          DNS_SERVER_DOMAIN = cfg.serverDomain;
          DNS_SERVER_RECURSION = "AllowOnlyForPrivateNetworks";
          DNS_SERVER_WEB_SERVICE_HTTP_PORT = toString cfg.webPort;
          DNS_SERVER_WEB_SERVICE_LOCAL_ADDRESSES = cfg.webServiceLocalAddresses;
        }
        // optionalAttrs (cfg.adminPasswordFile != null) {
          DNS_SERVER_ADMIN_PASSWORD_FILE = "%d/technitium-admin-password";
        };

      preStart = mkIf cfg.configureEncryptedDns ''
        set -euo pipefail

        state_dir="''${STATE_DIRECTORY:-/var/lib/technitium-dns-server}"
        cert_dir="$state_dir/tls"
        mkdir -p "$cert_dir"

        if [ ! -s "$cert_dir/${cfg.tlsCertificateDomain}.pfx" ]; then
          ${pkgs.openssl}/bin/openssl req \
            -x509 \
            -newkey rsa:4096 \
            -sha256 \
            -days 3650 \
            -nodes \
            -subj ${escapeShellArg "/CN=${cfg.tlsCertificateDomain}"} \
            -addext ${escapeShellArg "subjectAltName=${sanList}"} \
            -keyout "$cert_dir/${cfg.tlsCertificateDomain}.key.pem" \
            -out "$cert_dir/${cfg.tlsCertificateDomain}.crt.pem"

          ${pkgs.openssl}/bin/openssl pkcs12 \
            -export \
            -out "$cert_dir/${cfg.tlsCertificateDomain}.pfx" \
            -inkey "$cert_dir/${cfg.tlsCertificateDomain}.key.pem" \
            -in "$cert_dir/${cfg.tlsCertificateDomain}.crt.pem" \
            -passout pass:

          chmod 0600 "$cert_dir/${cfg.tlsCertificateDomain}."*
        fi
      '';

      serviceConfig = mkIf (cfg.adminPasswordFile != null) {
        LoadCredential = [ "technitium-admin-password:${cfg.adminPasswordFile}" ];
      };
    };

    systemd.services.technitium-dns-configure = mkIf cfg.configureEncryptedDns {
      after = [ "technitium-dns-server.service" ];
      description = "Configure Technitium encrypted DNS listeners";
      wants = [ "technitium-dns-server.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gnugrep
        pkgs.gnused
        pkgs.iproute2
        pkgs.systemd
      ];

      script = ''
        set -euo pipefail

        base="http://127.0.0.1:${toString cfg.webPort}"
        password_file=${adminPasswordFileArg}

        if [ "$password_file" = "" ] || [ ! -r "$password_file" ]; then
          echo "Technitium admin password file is unavailable." >&2
          exit 1
        fi

        admin_password="$(tr -d '\r\n' < "$password_file")"

        for attempt in {1..60}; do
          if curl -fsS "$base/" >/dev/null; then
            break
          fi

          if [ "$attempt" = 60 ]; then
            echo "Timed out waiting for Technitium web API." >&2
            exit 1
          fi

          sleep 1
        done

        login() {
          local password="$1"
          curl -fsS --get "$base/api/user/login" \
            --data-urlencode "user=admin" \
            --data-urlencode "pass=$password" \
            | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
        }

        token="$(login "$admin_password" || true)"

        if [ -z "$token" ]; then
          token="$(login admin || true)"
          if [ -z "$token" ]; then
            echo "Unable to authenticate to Technitium with managed or default admin password." >&2
            exit 1
          fi

          change_response="$(curl -fsS --get "$base/api/user/changePassword" \
            --data-urlencode "token=$token" \
            --data-urlencode "pass=$admin_password")"
          echo "$change_response" | grep -q '"status":"ok"'

          token="$(login "$admin_password")"
        fi

        settings_response="$(curl -fsS -X POST "$base/api/settings/set" \
          --data-urlencode "token=$token" \
          --data-urlencode "dnsServerDomain=${cfg.serverDomain}" \
          --data-urlencode "webServiceLocalAddresses=${cfg.webServiceLocalAddresses}" \
          --data-urlencode "webServiceHttpPort=${toString cfg.webPort}" \
          --data-urlencode "webServiceEnableTls=false" \
          --data-urlencode "enableDnsOverTls=${bool true}" \
          --data-urlencode "enableDnsOverHttps=${bool true}" \
          --data-urlencode "dnsOverTlsPort=${toString cfg.dnsOverTlsPort}" \
          --data-urlencode "dnsOverHttpsPort=${toString cfg.httpsPort}" \
          --data-urlencode "dnsTlsCertificatePath=${certificatePath}" \
          --data-urlencode "dnsTlsCertificatePassword=" \
          --data-urlencode "dnsOverHttpRealIpHeader=X-Real-IP")"
        echo "$settings_response" | grep -q '"status":"ok"'

        systemctl restart technitium-dns-server.service

        for attempt in {1..60}; do
          if curl -fsS "$base/" >/dev/null \
            && ss -ltn "( sport = :${toString cfg.dnsOverTlsPort} )" | grep -q ":${toString cfg.dnsOverTlsPort}" \
            && ss -ltn "( sport = :${toString cfg.httpsPort} )" | grep -q ":${toString cfg.httpsPort}"; then
            exit 0
          fi

          if [ "$attempt" = 60 ]; then
            echo "Timed out waiting for Technitium encrypted DNS listeners." >&2
            exit 1
          fi

          sleep 1
        done
      '';

      serviceConfig = {
        Type = "oneshot";
      };
    };
  };
}
