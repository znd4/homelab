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
  inventory = import ../inventory.nix;
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
      default = "home.znd4.dev";
      description = ''
        DNS zone for homelab services. Each service gets a name
        `<service>.''${domain}`. The name does not include the host, so a
        service can move to a different host or to Kubernetes without a new name.
      '';
    };
    lanAddress = lib.mkOption {
      type = lib.types.str;
      default =
        inventory.hosts.${config.networking.hostName}.ip
          or (throw "nix/inventory.nix has no host ${config.networking.hostName}. Add it, or set homelab.lanAddress.");
      defaultText = lib.literalExpression "(import nix/inventory.nix).hosts.<hostName>.ip";
      example = "10.0.20.10";
      description = ''
        The LAN IPv4 address of this host. It comes from nix/inventory.nix.
        The UniFi DHCP reservation and the homelab DNS records use the same value.
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

    # sops-nix decrypts secrets with the host SSH key (converted to age).
    # The bootstrap procedure creates this key before install. See docs/bootstrap.md.
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

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
