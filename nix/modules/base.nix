# Settings every homelab NixOS machine gets. Imported (via ./default.nix) by
# every host; individual knobs live under `homelab.*`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab;
  keys = import ../keys.nix;
in
{
  options.homelab = {
    adminUser = lib.mkOption {
      type = lib.types.str;
      default = "znd4";
      description = "Login user with passwordless sudo, reachable over SSH.";
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = keys.admins;
      description = "SSH public keys for the admin user and for initrd unlock.";
    };
    domain = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}.internal";
      defaultText = lib.literalExpression ''"''${config.networking.hostName}.internal"'';
      description = ''
        Per-machine DNS zone. Services are exposed as `<name>.''${domain}`; the
        router resolves `*.''${domain}` to this machine.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.authorizedKeys != [ ];
        message = "homelab.authorizedKeys is empty: add a public key to nix/keys.nix or you will be locked out.";
      }
    ];

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "@wheel" ];
    };

    users.mutableUsers = false;
    users.users.${cfg.adminUser} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };
    # Deploys go through `nixos-rebuild --target-host --sudo`; key-only SSH is
    # the authentication boundary.
    security.sudo.wheelNeedsPassword = false;

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    networking.firewall.enable = true;
    networking.useNetworkd = true;

    # mDNS so `<host>.local` works before the router knows about the machine.
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    time.timeZone = lib.mkDefault "America/New_York";

    environment.systemPackages = with pkgs; [
      git
      htop
      vim
    ];
  };
}
