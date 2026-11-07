# The address plan of the homelab: networks, hosts and VIPs.
#
# This file is the single source of truth for addresses. It is a plain
# attrset, not a NixOS module, so two consumers can read it:
#   - NixOS modules import it (homelab.lanAddress, the DNS VIP, CUPS and Caddy
#     access lists).
#   - Terragrunt reads it as JSON: `nix eval --json .#inventory`. The UniFi
#     units make networks, DHCP reservations and the DNS forward from it.
#
# Networks follow trust zones, not machine classes. All servers (NixOS hosts,
# Talos nodes, VIPs, the MetalLB pool) share the `servers` network, with an
# address range per class. See docs/decisions/0008-network-as-code.md.
#
# Flakes see only files that git tracks. Run `git add` after you change this file.
{
  domain = "home.znd4.dev";

  networks = {
    # The current default LAN, made by hand in UniFi. Terragrunt adopts it by
    # name and does not make it again.
    # TODO(bootstrap): set the real name, subnet and DHCP range of the default LAN.
    default = {
      name = "Default";
      adopt = true;
      vlan = null;
      subnet = "192.168.1.0/24";
      gateway = "192.168.1.1";
      dhcp = {
        start = "192.168.1.100";
        stop = "192.168.1.254";
      };
      trusted = true;
      canPrint = true;
    };

    # TODO(bootstrap): pick VLAN IDs and subnets that do not overlap the current networks.
    management = {
      name = "Management";
      adopt = false;
      vlan = 10;
      subnet = "10.0.10.0/24";
      gateway = "10.0.10.1";
      dhcp = {
        start = "10.0.10.100";
        stop = "10.0.10.199";
      };
      trusted = true;
      canPrint = false;
    };

    servers = {
      name = "Servers";
      adopt = false;
      vlan = 20;
      subnet = "10.0.20.0/24";
      gateway = "10.0.20.1";
      # Only for machines that are not in `hosts` yet, for example a new box
      # that boots the installer.
      dhcp = {
        start = "10.0.20.200";
        stop = "10.0.20.249";
      };
      # Fixed addresses by class. Keep them outside the DHCP range.
      ranges = {
        nixos = {
          start = "10.0.20.10";
          stop = "10.0.20.29";
        };
        talos = {
          start = "10.0.20.30";
          stop = "10.0.20.49";
        };
        vips = {
          start = "10.0.20.50";
          stop = "10.0.20.69";
        };
        metallb = {
          start = "10.0.20.100";
          stop = "10.0.20.149";
        };
      };
      trusted = true;
      canPrint = false;
    };

    iot = {
      name = "IoT";
      adopt = false;
      vlan = 30;
      subnet = "10.0.30.0/24";
      gateway = "10.0.30.1";
      dhcp = {
        start = "10.0.30.100";
        stop = "10.0.30.249";
      };
      trusted = false;
      canPrint = false;
    };

    guest = {
      name = "Guest";
      adopt = false;
      vlan = 40;
      subnet = "10.0.40.0/24";
      gateway = "10.0.40.1";
      dhcp = {
        start = "10.0.40.100";
        stop = "10.0.40.249";
      };
      trusted = false;
      canPrint = false;
    };
  };

  # Machines with a fixed address. `role` is nixos, talos or device.
  # The attribute name is the hostname. For NixOS hosts it must match
  # networking.hostName and the name in nix/hosts/.
  hosts = {
    hl01 = {
      role = "nixos";
      network = "servers";
      # TODO(bootstrap): the MAC address of the LAN interface (`ip -br link` on the installer).
      mac = null;
      ip = "10.0.20.10";
    };
  };

  # Floating addresses. They are in the `vips` range of the servers network.
  vips = {
    # keepalived moves it between the DNS hosts. UniFi forwards home.znd4.dev to it.
    dns = "10.0.20.53";
    # Later: the Kubernetes API (Talos VIP).
    kubeApi = "10.0.20.50";
  };
}
