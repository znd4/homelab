# hl01: first bare-metal NixOS box. It runs services until the Talos cluster
# exists, then hands them over.
{ lib, pkgs, ... }:
{
  imports = [ ./disko.nix ];

  networking.hostName = "hl01";
  system.stateVersion = "26.05";
  nixpkgs.hostPlatform = "x86_64-linux";

  # Hardware detection. Generated during install with
  # `nixos-anywhere --generate-hardware-config nixos-facter ./nix/hosts/hl01/facter.json`.
  # Until that file exists, fall back to the explicit initrd NIC list below.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;
  homelab.remoteUnlock.kernelModules = lib.mkIf (!builtins.pathExists ./facter.json) [
    # Common onboard and PCIe NICs. Harmless if absent: these are only loaded when matching hardware shows up.
    "r8169"
    "igc"
    "igb"
    "e1000e"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.services.cups = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };

  # Declare queues here instead of in the web UI, e.g.:
  # hardware.printers.ensurePrinters = [{
  #   name = "brother";
  #   deviceUri = "usb://Brother/...";   # `lpinfo -v` on the host
  #   model = "drv:///brlaser.drv/...";  # `lpinfo -m | grep -i brother`
  #   ppdOptions.PageSize = "Letter";
  # }];
  # hardware.printers.ensureDefaultPrinter = "brother";
}
