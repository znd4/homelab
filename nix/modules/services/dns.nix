# Authoritative DNS for the homelab zone (home.znd4.dev), on one or more hosts.
#
# The UniFi gateway stays the resolver for all clients. A UniFi "Forward
# Domain" rule sends only `home.znd4.dev` to `vip`. If the homelab is down,
# only homelab names stop to resolve. See docs/decisions/0006-dns.md.
#
# Records come from the flake: every host's `homelab.lanAddress` and every
# vhost in `homelab.reverseProxy.vhosts`. All DNS hosts build the same zone
# from the same commit. They do not need to synchronize at run time.
#
# HA: keepalived (VRRP) moves `vip` to a healthy DNS host. The health check
# queries the zone, so a host that runs but does not answer gives up the VIP.
#
# This server is not a recursive resolver. It answers only for `zone` and
# refuses all other queries.
{
  config,
  lib,
  pkgs,
  homelabHosts,
  flakeRev,
  flakeLastModified,
  ...
}:
let
  cfg = config.homelab.services.dns;
  zone = config.homelab.domain;

  # The `homelab` config of every host in the flake, this host included.
  hosts = lib.mapAttrs (_: h: h.config.homelab) homelabHosts;
  dnsHosts = lib.filterAttrs (_: h: h.services.dns.enable) hosts;
  peers = lib.mapAttrsToList (_: h: h.lanAddress) (
    lib.filterAttrs (n: _: n != config.networking.hostName) dnsHosts
  );

  hostRecords = lib.mapAttrsToList (name: h: {
    name = name;
    address = h.lanAddress;
  }) hosts;
  vhostRecords = lib.concatLists (
    lib.mapAttrsToList (
      _: h:
      map (sub: {
        name = sub;
        address = h.lanAddress;
      }) (lib.attrNames h.reverseProxy.vhosts)
    ) hosts
  );
  allRecords = hostRecords ++ vhostRecords ++ cfg.extraRecords;
  duplicates = lib.filter (n: lib.count (r: r.name == n) allRecords > 1) (
    lib.unique (map (r: r.name) allRecords)
  );

  zoneFile = pkgs.writeText "${zone}.zone" ''
    $ORIGIN ${zone}.
    $TTL ${toString cfg.ttl}
    @        IN SOA ns.${zone}. hostmaster.${zone}. ${toString flakeLastModified} 3600 600 86400 ${toString cfg.ttl}
    @        IN NS  ns.${zone}.
    ns       IN A   ${cfg.vip}
    version  IN TXT "${flakeRev}"
    ${lib.concatMapStringsSep "\n" (r: "${r.name} IN A ${r.address}") allRecords}
    ${lib.optionalString (cfg.wildcardTarget != null) "* IN A ${cfg.wildcardTarget}"}
  '';

  # Exit 0 only if the local server answers with the version record.
  healthCheck = pkgs.writeShellScript "homelab-dns-check" ''
    ${pkgs.dnsutils}/bin/dig +short +time=1 +tries=1 @127.0.0.1 version.${zone} TXT \
      | ${pkgs.gnugrep}/bin/grep -q .
  '';
in
{
  options.homelab.services.dns = {
    enable = lib.mkEnableOption "authoritative DNS for the homelab zone";
    vip = lib.mkOption {
      type = lib.types.str;
      example = "192.168.1.53";
      description = ''
        Floating IPv4 address for the DNS service. The UniFi Forward Domain
        rule points at it. It must be in the LAN subnet and outside the DHCP pool.
        Set the same value on every DNS host.
      '';
    };
    vipPrefixLength = lib.mkOption {
      type = lib.types.int;
      default = 24;
    };
    interface = lib.mkOption {
      type = lib.types.str;
      example = "enp1s0";
      description = "LAN interface that holds the VIP. Find it with `ip -br link` on the host.";
    };
    priority = lib.mkOption {
      type = lib.types.ints.between 1 254;
      default = 100;
      description = "VRRP priority. The healthy host with the highest priority holds the VIP. Give each DNS host a different value.";
    };
    virtualRouterId = lib.mkOption {
      type = lib.types.ints.between 1 255;
      default = 53;
      description = "VRRP router ID. It must be the same on all DNS hosts and unique on the LAN.";
    };
    ttl = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Record TTL in seconds. A low TTL keeps the time short when hosts give different answers during a deploy.";
    };
    wildcardTarget = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "If set, all names that have no record resolve to this address. Leave it null to make unknown names fail (NXDOMAIN).";
    };
    extraRecords = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            address = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
      description = "A records for devices that are not NixOS hosts in this flake.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = duplicates == [ ];
        message = "homelab DNS: these names have more than one record: ${toString duplicates}";
      }
      {
        assertion = lib.length (lib.unique (lib.mapAttrsToList (_: h: h.services.dns.vip) dnsHosts)) == 1;
        message = "homelab DNS: all DNS hosts must use the same homelab.services.dns.vip.";
      }
    ];

    # Let CoreDNS bind the VIP when this host does not hold it.
    boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

    services.coredns = {
      enable = true;
      config = ''
        ${zone}:53 {
          bind 127.0.0.1 ${config.homelab.lanAddress} ${cfg.vip}
          file ${zoneFile}
          errors
          log
        }
        .:53 {
          bind 127.0.0.1 ${config.homelab.lanAddress} ${cfg.vip}
          acl {
            block
          }
        }
      '';
    };

    # A switch fails if CoreDNS starts but does not answer. The deploy then
    # stops before the next host (see docs/decisions/0006-dns.md).
    systemd.services.coredns.serviceConfig.ExecStartPost = pkgs.writeShellScript "coredns-ready" ''
      for _ in $(seq 20); do
        ${healthCheck} && exit 0
        sleep 0.5
      done
      echo "CoreDNS does not answer for version.${zone}" >&2
      exit 1
    '';

    networking.firewall = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };

    services.keepalived = {
      enable = true;
      openFirewall = true;
      enableScriptSecurity = true;
      vrrpScripts.coredns = {
        script = toString healthCheck;
        interval = 2;
        fall = 2;
        rise = 2;
        user = "nobody";
      };
      vrrpInstances.homelab-dns = {
        inherit (cfg) interface priority virtualRouterId;
        state = "BACKUP";
        # Unicast: UniFi IGMP snooping can drop VRRP multicast.
        unicastSrcIp = if peers == [ ] then null else config.homelab.lanAddress;
        unicastPeers = peers;
        virtualIps = [ { addr = "${cfg.vip}/${toString cfg.vipPrefixLength}"; } ];
        trackScripts = [ "coredns" ];
      };
    };

    environment.systemPackages = [ pkgs.dnsutils ];
  };
}
