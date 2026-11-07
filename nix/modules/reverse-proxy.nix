# Caddy in front of web UIs, one virtual host per service:
#
#   homelab.reverseProxy.vhosts.printer.upstream = "localhost:631";
#   # -> https://printer.<host>.internal
#
# Service modules register their vhost here instead of configuring Caddy
# directly, so TLS and access policy are decided in one place.
#
# TLS: `tls internal` (Caddy's own CA) for now, because `.internal` names
# cannot get public certificates. Browsers need Caddy's root CA installed once:
# /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
# See docs/decisions/0003-names-and-tls.md for the planned move to a real
# domain with DNS-01.
{ config, lib, ... }:
let
  cfg = config.homelab.reverseProxy;
  inherit (config.homelab) domain;
in
{
  options.homelab.reverseProxy = {
    lanCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "192.168.0.0/16"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "fd00::/8"
      ];
      description = "Source ranges allowed to reach `lanOnly` vhosts. Narrow this to the real LAN/VLANs.";
    };
    vhosts = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            upstream = lib.mkOption {
              type = lib.types.str;
              example = "localhost:8080";
            };
            lanOnly = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Return 403 to clients outside `lanCidrs`.";
            };
            upstreamHost = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Rewrite the Host header sent upstream, for backends that check it (e.g. CUPS).";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf (cfg.vhosts != { }) {
    services.caddy = {
      enable = true;
      virtualHosts = lib.mapAttrs' (
        name: vhost:
        lib.nameValuePair "${name}.${domain}" {
          extraConfig = lib.concatStringsSep "\n" (
            [ "tls internal" ]
            ++ lib.optionals vhost.lanOnly [
              "@outside not remote_ip ${lib.concatStringsSep " " cfg.lanCidrs}"
              "respond @outside 403"
            ]
            ++ [
              (
                if vhost.upstreamHost == null then
                  "reverse_proxy ${vhost.upstream}"
                else
                  ''
                    reverse_proxy ${vhost.upstream} {
                      header_up Host ${vhost.upstreamHost}
                    }''
              )
            ]
          );
        }
      ) cfg.vhosts;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
