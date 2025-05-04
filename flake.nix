{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      nixos-generators,
      self,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      top@{
        config,
        withSystem,
        moduleWithSystem,
        ...
      }:
      {
        imports = [
          # To import a flake module
          # 1. Add foo to inputs
          # 2. Add foo as a parameter to the outputs function
          # 3. Add here: foo.flakeModule

        ];
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        perSystem =
          {
            config,
            self',
            inputs',
            pkgs,
            system,
            ...
          }:
          {
            # Per-system attributes can be defined here. The self' and inputs'
            # module parameters provide easy access to attributes of the same
            # system.

            # Equivalent to  inputs'.nixpkgs.legacyPackages.hello;
            packages.default = pkgs.hello;
          };
        flake = {
          # The usual flake attributes can be defined here, including system-
          # agnostic ones like nixosModule and system-enumerating ones, although
          # those are more easily expressed in perSystem.
          nixosModules.corednsMachine = {
            imports = [
              nixos-generators.nixosModules.all-formats
              (
                { ... }:
                {
                  system.stateVersion = "24.11";
                }
              )
              (
                { pkgs, lib, ... }:
                {
                  services.coredns.enable = true;
                  # services.coredns.package = pkgs.coredns.override {
                  #   externalPlugins = [
                  #     {
                  #       name = "blocklist";
                  #       repo = "github.com/relekang/coredns-blocklist";
                  #       version = "v1.13.0";
                  #     }
                  #   ];
                  #   # fake (placeholder) SRI hash
                  #   # vendorHash =pkgs.lib.fakeSha256;
                  #   # fake SRI hash
                  #   vendorHash = "sha256-uf1qj2JgYF7kCTx0Iuguoo8t7EZjBKGULvg7+j19D8s=";
                  # };
                  services.coredns.config = ''
                    . {
                      log
                      prometheus


                      # load from url
                      blocklist https://mirror1.malwaredomains.com/files/justdomains {
                        # if CoreDNS listens at 53, you need another DNS to bootstrap the download
                        bootstrap_dns 1.1.1.1:53
                      }

                      # blocklist blocklist.txt

                      forward . 1.1.1.1 1.0.0.1
                    }
                  '';
                }
              )
            ];
            nixpkgs.hostPlatform = "x86_64-linux";
            # # customize an existing format
            # formatConfigs.vmware =
            #   { config, ... }:
            #   {
            #     services.openssh.enable = true;
            #   };
          };
          nixosConfigurations.corednsMachine = nixpkgs.lib.nixosSystem {
            modules = [ self.nixosModules.corednsMachine ];
          };
        };
      }
    );
}
