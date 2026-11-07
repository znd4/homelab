# Bootstrap ISO: a stock NixOS minimal installer that accepts our SSH keys as
# root, so a fresh machine can be installed remotely with nixos-anywhere right
# after it boots from USB. Install steps are in docs/bootstrap.md.
#
#   nix build .#installer-iso
{
  modulesPath,
  lib,
  pkgs,
  ...
}:
let
  keys = import ./keys.nix;
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "nixos-installer";

  users.users.root.openssh.authorizedKeys.keys = keys.admins;
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = lib.mkForce false;
  };

  # Reachable as nixos-installer.local without looking up its DHCP lease.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  assertions = [
    {
      assertion = keys.admins != [ ];
      message = "nix/keys.nix has no admin keys; the installer would be unreachable over SSH.";
    }
  ];

  # `nixos-facter > facter.json` produces the host's hardware report.
  environment.systemPackages = [ pkgs.nixos-facter ];

  boot.zfs.forceImportRoot = false;
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
}
