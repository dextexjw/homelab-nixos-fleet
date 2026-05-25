# ============================================================================
# FLEET HOST DEFINITIONS
# Single source of truth for all host information
# ============================================================================

{
  gateway-vm = {
    arch = "x86_64-linux";
    domain = "home.arpa";
    fqdn = "gateway.home.arpa";
    ip = "10.2.20.112";
    gateway = "10.2.20.1";
    nameservers = [
      "10.2.20.1"
      "9.9.9.9"
    ];
    user = "smoke";
    tags = [
      "control-plane"
      "gateway"
    ];
    timezone = "America/New_York";
    vm = {
      cores = 4;
      disk = "/dev/sda";
      id = "112";
      name = "gateway-vm";
      ramGB = 8;
    };
  };

  media-vm = {
    arch = "x86_64-linux";
    domain = "home.arpa";
    fqdn = "media.home.arpa";
    ip = "10.2.20.113";
    gateway = "10.2.20.1";
    nameservers = [
      "10.2.20.1"
      "9.9.9.9"
    ];
    user = "smoke";
    tags = [
      "media"
    ];
    timezone = "America/New_York";
    vm = {
      cores = 4;
      disk = "/dev/sda";
      id = "113";
      name = "media-vm";
      ramGB = 8;
    };
  };
}
