# hl01: the first bare-metal NixOS host. It runs services until the Talos
# cluster exists. Then the services move to the cluster.
{ lib, pkgs, ... }:
{
  imports = [ ./disko.nix ];

  networking.hostName = "hl01";
  system.stateVersion = "26.05";
  nixpkgs.hostPlatform = "x86_64-linux";

  # homelab.lanAddress comes from nix/inventory.nix.

  # Hardware detection. The bootstrap procedure creates facter.json
  # (docs/bootstrap.md). Until it exists, the explicit initrd NIC list below applies.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;
  homelab.remoteUnlock.kernelModules = lib.mkIf (!builtins.pathExists ./facter.json) [
    # Common onboard and PCIe NICs. The kernel loads a module only if the hardware is present.
    "r8169"
    "igc"
    "igb"
    "e1000e"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Secrets for this host. The bootstrap procedure creates this file.
  sops.defaultSopsFile = ./secrets.yaml;

  # The target of the _acme-challenge.home.znd4.dev CNAME. acme.znd4.dev is a
  # deSEC zone that DNSimple delegates to (docs/bootstrap.md#prepare-the-acme-challenge-zone).
  homelab.reverseProxy.acme.challengeDomain = "_acme-challenge.acme.znd4.dev";

  homelab.services.dns = {
    enable = true;
    # The VIP comes from nix/inventory.nix (vips.dns).
    # TODO(bootstrap): the LAN interface name from `ip -br link` on the installer.
    #   Runbook: docs/bootstrap.md#get-the-hardware-facts (the interface step).
    interface = "enp1s0";
    priority = 150;
  };

  homelab.services.cups = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };

  # Declare printer queues here, not in the web UI. Example:
  # hardware.printers.ensurePrinters = [{
  #   name = "brother";
  #   deviceUri = "usb://Brother/...";   # `lpinfo -v` on the host
  #   model = "drv:///brlaser.drv/...";  # `lpinfo -m | grep -i brother`
  #   ppdOptions.PageSize = "Letter";
  # }];
  # hardware.printers.ensureDefaultPrinter = "brother";
}
