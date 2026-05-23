# ============================================================================
# FLEET HOST DEFINITIONS
# Single source of truth for all host information
# ============================================================================

{
  gateway-vm = {
    ip = "10.2.20.112";
    user = "smoke";
    tags = [
      "control-plane"
      "monitoring"
    ];
  };

  media-vm = {
    ip = "10.2.20.113";
    user = "smoke";
    tags = [
      "git"
    ];
  };
}
