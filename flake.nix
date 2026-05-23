{
  # ============================================================================
  # FLAKE INPUTS - External dependencies and packages
  # ============================================================================

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  # ============================================================================
  # FLAKE OUTPUTS - What this flake provides
  # ============================================================================

  outputs =
    {
      nixpkgs,
      colmena,
      sops-nix,
      ...
    }:
    let
      # Import host definitions from single source of truth
      hosts = import ./hosts.nix;

      ephemeralSshOptions = [
        "-o"
        "CheckHostIP=no"
        "-o"
        "GlobalKnownHostsFile=/dev/null"
        "-o"
        "LogLevel=ERROR"
        "-o"
        "StrictHostKeyChecking=no"
        "-o"
        "UpdateHostKeys=no"
        "-o"
        "UserKnownHostsFile=/dev/null"
      ];

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

      devShells.x86_64-linux.default =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.mkShell {
          buildInputs = [
            colmena.packages.x86_64-linux.colmena
            pkgs.age
            pkgs.restic
            pkgs.sops
          ];
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

        gateway-vm = {
          deployment = {
            sshOptions = ephemeralSshOptions;
            targetHost = hosts.gateway-vm.ip;
            targetUser = hosts.gateway-vm.user;
            tags = hosts.gateway-vm.tags;
          };

          imports = [
            ./hosts/gateway-vm/configuration.nix
          ];
        };

        media-vm = {
          deployment = {
            sshOptions = ephemeralSshOptions;
            targetHost = hosts.media-vm.ip;
            targetUser = hosts.media-vm.user;
            tags = hosts.media-vm.tags;
          };

          imports = [
            sops-nix.nixosModules.sops
            ./hosts/media-vm/configuration.nix
          ];
        };
      };
    };
}
