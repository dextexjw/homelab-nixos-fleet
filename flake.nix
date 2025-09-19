{
  # ============================================================================
  # FLAKE INPUTS - External dependencies and packages
  # ============================================================================

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
  };

  # ============================================================================
  # FLAKE OUTPUTS - What this flake provides
  # ============================================================================

  outputs =
    { nixpkgs, colmena, ... }:
    let
      # Import host definitions from single source of truth
      hosts = import ./hosts.nix;

      # For scaling up your homelab, you'd likely want automated host generation:
      # mkHost = name: hostConfig: {
      #   deployment = {
      #     targetHost = hostConfig.ip;
      #     targetUser = hostConfig.user;
      #     tags = hostConfig.tags;
      #   };
      #   imports = [ ./hosts/${name}/configuration.nix ];
      # };
      # hostConfigs = builtins.mapAttrs mkHost hosts;
    in
    {
      # ==========================================================================
      # DEVELOPMENT SHELL - Local development environment
      # ==========================================================================

      devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
        buildInputs = [ colmena.packages.x86_64-linux.colmena ];
      };

      # ==========================================================================
      # COLMENA HIVE - Fleet deployment configuration
      # ==========================================================================

      colmenaHive = colmena.lib.makeHive {
        # ========================================================================
        # GLOBAL CONFIGURATION - Settings applied to all hosts
        # ========================================================================

        meta = {
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ ];
          };
        };

        # ========================================================================
        # HOST DEFINITIONS - Individual server configurations
        # ========================================================================

        alpha = {
          deployment = {
            targetHost = hosts.alpha.ip;
            targetUser = hosts.alpha.user;
            tags = hosts.alpha.tags;
          };

          imports = [
            ./hosts/alpha/configuration.nix
          ];
        };

        bravo = {
          deployment = {
            targetHost = hosts.bravo.ip;
            targetUser = hosts.bravo.user;
            tags = hosts.bravo.tags;
          };

          imports = [
            ./hosts/bravo/configuration.nix
          ];
        };

        charlie = {
          deployment = {
            targetHost = hosts.charlie.ip;
            targetUser = hosts.charlie.user;
            tags = hosts.charlie.tags;
          };

          imports = [
            ./hosts/charlie/configuration.nix
          ];
        };
      };
    };
}
