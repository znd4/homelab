{
  description = "znd4's homelab: NixOS hosts, and later Talos/Kubernetes and network config";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      disko,
      self,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        {
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nixos-anywhere
              nixos-rebuild-ng
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
            ./nix/modules
          ];
        };

        nixosConfigurations = {
          hl01 = nixpkgs.lib.nixosSystem {
            modules = [
              self.nixosModules.default
              ./nix/hosts/hl01
            ];
          };
          installer = nixpkgs.lib.nixosSystem {
            modules = [ ./nix/installer.nix ];
          };
        };

        # Built-in image builder (NixOS 25.05+, replaces nixos-generators).
        # Any host can also be turned into an image directly, e.g.
        #   nixos-rebuild build-image --flake .#hl01 --image-variant qemu-efi
        packages.x86_64-linux.installer-iso =
          self.nixosConfigurations.installer.config.system.build.isoImage;
      };
    };
}
