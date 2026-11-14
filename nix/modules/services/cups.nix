# Network print server.
#
# Two paths in:
#   - Printing: clients talk IPP to cupsd on :631 directly. Avahi advertises the
#     queues (IPP Everywhere / AirPrint), so macOS, iOS, Android and Linux find
#     them with no setup. This path does NOT go through Caddy, because mDNS
#     advertises <host>.local:631.
#   - Admin web UI: https://printer.home.znd4.dev via Caddy (LAN only). CUPS
#     rejects unknown Host headers (DNS-rebinding protection), so Caddy rewrites
#     Host to localhost. Anything that changes config still needs a login in
#     CUPS' SystemGroup. Prefer declaring printers in Nix (`hardware.printers`)
#     over clicking them together in the UI.
#
# Exposure: cupsd listens on all interfaces but only answers `lanCidrs`. Never
# port-forward 631.
#
# VLANs: the CUPS host is in the servers network, and clients are in other
# networks. mDNS does not cross VLANs by itself. Turn on the UniFi mDNS proxy
# (multicast DNS) for the servers network and the client networks, or clients
# do not find the printer. See docs/decisions/0008-network-as-code.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.services.cups;
  inventory = import ../../inventory.nix;
in
{
  options.homelab.services.cups = {
    enable = lib.mkEnableOption "CUPS print server shared on the LAN";
    drivers = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.brlaser ]";
      description = "Printer drivers. Leave empty for driverless (IPP Everywhere) printers.";
    };
    lanCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.mapAttrsToList (_: n: n.subnet) (
        lib.filterAttrs (_: n: n.canPrint) inventory.networks
      );
      defaultText = lib.literalExpression "subnets of the networks with canPrint = true in nix/inventory.nix";
      description = ''
        Client networks that can print. CUPS also always answers localhost,
        which is how Caddy reaches the web UI.
      '';
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "printer";
    };
  };

  config = lib.mkIf cfg.enable {
    services.printing = {
      enable = true;
      inherit (cfg) drivers;
      listenAddresses = [ "*:631" ];
      allowFrom = [ "localhost" ] ++ cfg.lanCidrs;
      defaultShared = true;
      browsing = true;
      openFirewall = true;
      # The web UI's own links and redirects use this name.
      extraConf = ''
        ServerAlias ${cfg.subdomain}.${config.homelab.domain}
        ServerAlias ${config.networking.hostName}.local
      '';
    };

    # This host shares printers; it doesn't need to discover other servers' printers.
    services.printing.browsed.enable = false;

    services.avahi = {
      enable = true;
      openFirewall = true;
      publish = {
        enable = true;
        userServices = true;
      };
    };

    homelab.reverseProxy.vhosts.${cfg.subdomain} = {
      upstream = "localhost:631";
      upstreamHost = "localhost";
    };

    environment.systemPackages = [ pkgs.cups ];
  };
}
