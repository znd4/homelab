{
  description = "znd4's homelab: NixOS hosts, and later Talos/Kubernetes and network config";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      disko,
      sops-nix,
      deploy-rs,
      self,
      ...
    }:
    let
      # Homelab hosts: the NixOS machines in nix/hosts/. The installer is not one.
      hostNames = [ "hl01" ];

      mkHost =
        name:
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            # Each host reads the config of all hosts, for example to build the
            # DNS zone. All hosts build from one commit, so they agree.
            homelabHosts = nixpkgs.lib.genAttrs hostNames (n: self.nixosConfigurations.${n});
            flakeRev = self.rev or self.dirtyRev or "unknown";
            flakeLastModified = self.lastModified or 0;
          };
          modules = [
            self.nixosModules.default
            ./nix/hosts/${name}
          ];
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem =
        { pkgs, inputs', ... }:
        {
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              inputs'.deploy-rs.packages.default
              nixos-anywhere
              nixos-rebuild-ng
              sops
              age
              ssh-to-age
              dnsutils
              opentofu
              terragrunt
            ];
          };
          formatter = pkgs.nixfmt-rfc-style;
        };

      flake = {
        nixosModules.default = {
          imports = [
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            ./nix/modules
          ];
        };

        # Address plan for NixOS and for Terragrunt (`nix eval --json .#inventory`).
        inventory = import ./nix/inventory.nix;

        nixosConfigurations = nixpkgs.lib.genAttrs hostNames mkHost // {
          installer = nixpkgs.lib.nixosSystem {
            modules = [ ./nix/installer.nix ];
          };
        };

        # `deploy .#hl01` builds on the target and activates the new config.
        # If the host does not confirm the activation over SSH, deploy-rs
        # restores the previous generation (magic rollback).
        # Deploy the DNS hosts one at a time. See docs/decisions/0006-dns.md.
        deploy.nodes = nixpkgs.lib.genAttrs hostNames (name: {
          # The LAN address, not mDNS: it works when mDNS does not.
          hostname = self.nixosConfigurations.${name}.config.homelab.lanAddress;
          sshUser = "znd4";
          user = "root";
          remoteBuild = true;
          profiles.system.path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.${name};
        });

        checks.x86_64-linux = deploy-rs.lib.x86_64-linux.deployChecks self.deploy // {
          dns-vm = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest (
            import ./nix/tests/dns.nix { inherit self; }
          );
        };

        # Built-in image builder (NixOS 25.05+). It replaces nixos-generators.
        # Any host can also become an image, for example:
        #   nixos-rebuild build-image --flake .#hl01 --image-variant qemu-efi
        packages.x86_64-linux.installer-iso =
          self.nixosConfigurations.installer.config.system.build.isoImage;
      };
    };
}
