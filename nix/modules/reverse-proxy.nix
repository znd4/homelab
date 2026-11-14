# Caddy in front of web UIs. Each service registers a subdomain:
#
#   homelab.reverseProxy.vhosts.printer.upstream = "localhost:631";
#   # -> https://printer.home.znd4.dev
#
# Caddy serves one site, `*.<domain>`, with one wildcard certificate. Each
# vhost is a `host` matcher in that site. With one wildcard certificate, the
# public Certificate Transparency logs show only `*.home.znd4.dev`, not the
# name of each service.
#
# TLS modes:
#   - "acme" (default): Let's Encrypt with a DNS-01 challenge. Caddy writes the
#     challenge TXT record in a delegated deSEC zone. A permanent CNAME in the
#     main zone points `_acme-challenge.<domain>` at that zone. The token on
#     this host thus cannot change the main zone (MX, SPF, DKIM).
#     See docs/decisions/0003-names-and-tls.md.
#   - "internal": Caddy's local CA. Clients must trust its root certificate.
#     Use it for tests, or when DNS-01 is not available.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.reverseProxy;
  inventory = import ../inventory.nix;
  inherit (config.homelab) domain;

  vhostBlock =
    name: vhost:
    let
      upstream =
        if vhost.upstreamHost == null then
          "reverse_proxy ${vhost.upstream}"
        else
          ''
            reverse_proxy ${vhost.upstream} {
              header_up Host ${vhost.upstreamHost}
            }'';
    in
    ''
      @${name} host ${name}.${domain}
      handle @${name} {
        ${lib.optionalString vhost.lanOnly "import lan_only"}
        ${upstream}
      }
    '';

  tlsBlock =
    if cfg.tls == "internal" then
      "tls internal"
    else
      ''
        tls {
          dns desec {
            token {env.DESEC_TOKEN}
          }
          dns_challenge_override_domain ${cfg.acme.challengeDomain}
        }'';
in
{
  options.homelab.reverseProxy = {
    tls = lib.mkOption {
      type = lib.types.enum [
        "acme"
        "internal"
      ];
      default = "acme";
      description = "How Caddy gets the `*.<domain>` certificate. See the comment at the top of this file.";
    };
    acme = {
      email = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional ACME account email. Let's Encrypt can send account notices to it.";
      };
      challengeDomain = lib.mkOption {
        type = lib.types.str;
        example = "_acme-challenge.acme.znd4.dev";
        description = ''
          The target of the CNAME `_acme-challenge.<domain>`. Caddy writes the
          DNS-01 TXT record at this name in deSEC.
        '';
      };
      tokenSecret = lib.mkOption {
        type = lib.types.str;
        default = "desec-token";
        description = "Name of the sops secret that holds the deSEC API token.";
      };
    };
    lanCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.mapAttrsToList (_: n: n.subnet) (
        lib.filterAttrs (_: n: n.trusted) inventory.networks
      );
      defaultText = lib.literalExpression "subnets of the trusted networks in nix/inventory.nix";
      description = "Source ranges that can reach `lanOnly` vhosts. IoT and guest networks are not in the default.";
    };
    vhosts = lib.mkOption {
      default = { };
      description = "Web UIs on this host, by subdomain.";
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
              description = "Replace the Host header sent upstream. Some backends check it (for example, CUPS).";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf (cfg.vhosts != { }) (
    lib.mkMerge [
      {
        services.caddy = {
          enable = true;
          email = lib.mkIf (cfg.acme.email != null) cfg.acme.email;
          extraConfig = ''
            (lan_only) {
              @outside not remote_ip ${lib.concatStringsSep " " cfg.lanCidrs}
              respond @outside 403
            }
          '';
          virtualHosts."*.${domain}".extraConfig = ''
            ${tlsBlock}

            ${lib.concatStringsSep "\n" (lib.mapAttrsToList vhostBlock cfg.vhosts)}

            handle {
              respond 404
            }
          '';
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];
      }

      (lib.mkIf (cfg.tls == "acme") {
        services.caddy.package = pkgs.caddy.withPlugins {
          plugins = [ "github.com/caddy-dns/desec@v1.1.0" ];
          hash = "sha256-HrLRezw+q5+dRdJS662686n7xsImSxNb3UqlSo61R8E=";
        };

        sops.secrets.${cfg.acme.tokenSecret} = { };
        sops.templates."caddy.env" = {
          content = "DESEC_TOKEN=${config.sops.placeholder.${cfg.acme.tokenSecret}}";
          owner = config.services.caddy.user;
        };
        systemd.services.caddy.serviceConfig.EnvironmentFile = config.sops.templates."caddy.env".path;
      })
    ]
  );
}
