# VM test for homelab DNS, keepalived failover and the Caddy -> CUPS proxy.
#
#   nix build .#checks.x86_64-linux.dns-vm      (needs KVM)
#
# Nodes: two DNS hosts (dns1 has the higher VRRP priority) and one client.
# The test uses `tls = "internal"`, because it has no internet access.
{ self }:
{ lib, ... }:
let
  vip = "192.168.1.53";
  dummyKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl test";

  dnsHost =
    priority:
    {
      config,
      nodes,
      pkgs,
      ...
    }:
    {
      imports = [ self.nixosModules.default ];
      _module.args = {
        homelabHosts = lib.mapAttrs (_: n: { config = n; }) { inherit (nodes) dns1 dns2; };
        flakeRev = "test-rev";
        flakeLastModified = 1;
      };

      homelab = {
        authorizedKeys = [ dummyKey ];
        lanAddress = config.networking.primaryIPAddress;
        remoteUnlock.enable = false;
        reverseProxy.tls = "internal";
        # The test network, not the subnets in nix/inventory.nix.
        reverseProxy.lanCidrs = [ "192.168.1.0/24" ];
        services.dns = {
          enable = true;
          inherit vip priority;
          interface = "eth1";
        };
      };
      networking.useNetworkd = lib.mkForce false;
    };
in
{
  name = "homelab-dns";

  nodes = {
    dns1 =
      { ... }:
      {
        imports = [ (dnsHost 150) ];
        homelab.services.cups.enable = true;
      };
    dns2 = dnsHost 100;
    client =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          pkgs.dnsutils
          pkgs.curl
        ];
      };
  };

  testScript =
    { nodes, ... }:
    let
      dns1 = nodes.dns1.networking.primaryIPAddress;
      zone = "home.znd4.dev";
    in
    ''
      def dig(args):
          return client.succeed(f"dig +short +time=1 +tries=3 @${vip} {args}").strip()

      def vip_holder():
          for m in (dns1, dns2):
              if m.execute("ip -4 addr show eth1 | grep -q ${vip}")[0] == 0:
                  return m.name
          return None

      start_all()
      for m in (dns1, dns2):
          m.wait_for_unit("coredns.service")
          # nixpkgs starts keepalived from a timer, 5s after network-online.
          m.wait_until_succeeds("systemctl is-active keepalived.service", timeout=60)
      client.wait_for_unit("multi-user.target")

      with subtest("dns1 has the higher priority and holds the VIP"):
          dns1.wait_until_succeeds("ip -4 addr show eth1 | grep -q ${vip}", timeout=60)
          assert vip_holder() == "dns1", vip_holder()

      with subtest("records come from the hosts and the vhosts"):
          client.wait_until_succeeds("dig +short @${vip} printer.${zone} | grep -q .", timeout=60)
          assert dig("printer.${zone}") == "${dns1}", dig("printer.${zone}")
          assert dig("dns2.${zone}") == "${nodes.dns2.networking.primaryIPAddress}"
          assert dig("version.${zone} TXT") == '"test-rev"', dig("version.${zone} TXT")

      with subtest("unknown names in the zone are NXDOMAIN"):
          client.succeed("dig @${vip} nothing.${zone} | grep -q 'status: NXDOMAIN'")

      with subtest("the server refuses names outside the zone"):
          client.succeed("dig @${vip} example.com | grep -q 'status: REFUSED'")

      with subtest("the VIP moves to dns2 when CoreDNS on dns1 stops"):
          dns1.succeed("systemctl stop coredns.service")
          dns2.wait_until_succeeds("ip -4 addr show eth1 | grep -q ${vip}", timeout=30)
          dns1.wait_until_fails("ip -4 addr show eth1 | grep -q ${vip}", timeout=30)
          assert dig("printer.${zone}") == "${dns1}"

      with subtest("the VIP goes back to dns1 when CoreDNS on dns1 starts"):
          dns1.succeed("systemctl start coredns.service")
          dns1.wait_until_succeeds("ip -4 addr show eth1 | grep -q ${vip}", timeout=30)
          dns2.wait_until_fails("ip -4 addr show eth1 | grep -q ${vip}", timeout=30)

      with subtest("Caddy serves the CUPS web UI through the Host rewrite"):
          # CUPS starts on demand through cups.socket.
          dns1.wait_for_unit("cups.socket")
          dns1.wait_for_unit("caddy.service")
          dns1.wait_for_open_port(443)
          url = "https://printer.${zone}/"
          resolve = "--resolve printer.${zone}:443:${dns1} --resolve other.${zone}:443:${dns1}"
          client.wait_until_succeeds(f"curl -sfk {resolve} {url} | grep -qi cups", timeout=60)
          code = client.succeed(f"curl -sk -o /dev/null -w '%{{http_code}}' {resolve} https://other.${zone}/")
          assert code == "404", code
    '';
}
