# 0008: Network as code

**Status:** accepted · 2026-11. Not applied yet. The network is still made by
hand until the first `apply`.

## Decision

- `nix/inventory.nix` is the single source of truth for addresses: networks,
  hosts, VIPs and pools.
- NixOS modules read the inventory. OpenTofu reads it through
  `nix eval --json .#inventory`.
- Networks follow trust zones. Machine classes get address ranges inside one
  servers network, not their own subnets.
- Terragrunt stacks manage UniFi with the `ubiquiti-community/unifi` provider.
  The stack has three units: `networks`, `clients` and `dns`.
- Terragrunt adopts the current config made by hand. It does not make the
  config again.

## One inventory for NixOS and OpenTofu

Before this decision, `nix/hosts/hl01/default.nix` held the address of hl01.
A DHCP reservation in UniFi held the same address. Two copies can disagree.

Now each value has one place:

| Value | Inventory | Readers |
| --- | --- | --- |
| Host IP | `hosts.<name>.ip` | `homelab.lanAddress`, DNS records, deploy-rs, `unifi_client.fixed_ip` |
| Host MAC | `hosts.<name>.mac` | `unifi_client.mac` |
| DNS VIP | `vips.dns` | keepalived, CoreDNS, the Forward Domain |
| Subnets | `networks.<name>.subnet` | Caddy and CUPS access lists, `unifi_network` |

The inventory is a plain attrset, not a NixOS module. A module would make the
JSON export depend on a full NixOS evaluation. A plain file is fast to read and
easy to check.

The inventory has no MAC address for a host until bootstrap. The `clients`
unit skips a host without a MAC address.

## Subnets by trust zone

| Network | VLAN | Contents | Trusted |
| --- | --- | --- | --- |
| Default | none | Laptops and phones. This is the current LAN. | yes |
| Management | 10 | UniFi devices, BMC and IPMI | yes |
| Servers | 20 | NixOS hosts, Talos nodes, VIPs, MetalLB pool | yes |
| IoT | 30 | Smart devices | no |
| Guest | 40 | Guests | no |

The VLAN IDs and subnets are placeholders until bootstrap.

All server classes share one network, for these reasons:

- Ceph and Kubernetes send much traffic between nodes. In one network, that
  traffic stays on the switches. Between networks, all of it goes through the
  UniFi gateway.
- keepalived (VRRP) and MetalLB in L2 mode need their members in the same L2
  segment.
- A firewall between NixOS hosts and Talos nodes adds little. Both are
  servers that I manage.

Inside the servers network, each class has an address range:

| Range | Addresses |
| --- | --- |
| NixOS hosts | .10 to .29 |
| Talos nodes | .30 to .49 |
| VIPs | .50 to .69 |
| MetalLB pool | .100 to .149 |
| DHCP (new machines) | .200 to .249 |

A separate storage network can come later, if Ceph needs its own cluster
network. That decision is about traffic, not about a machine class.

## Effects on services

- **Caddy:** `lanOnly` services accept only the trusted networks. IoT and
  guest devices get 403.
- **CUPS:** only the networks with `canPrint = true` can print. By default,
  that is only the default LAN.
- **mDNS:** the printer host is in the servers network, and the clients are in
  the default LAN. mDNS does not cross VLANs. Turn on the UniFi mDNS proxy for
  both networks. Without it, clients do not find the printer.

## Terragrunt stack layout

```
infra/root.hcl                       inventory, provider, backend, encryption
infra/catalog/modules/<module>/      OpenTofu modules
infra/catalog/units/<unit>/          Terragrunt units
infra/live/home/terragrunt.stack.hcl the stack
```

- The units read the inventory from `root.hcl`. The stack `values` hold only
  wiring, for example the path of the `networks` unit.
- `clients` and `dns` depend on `networks`. Terragrunt applies `networks` first.
- The modules use `cidrcontains` checks: each gateway and DHCP range must be in
  its subnet, and each host IP must be in its network.

## Adoption of the current config

- `unifi_network` adopts a network with `adopt = true` through an `import`
  block. The import ID is the network name (`name=<name>`).
- `unifi_client` uses `allow_existing = true`, so tofu takes over a known client.
- The first plan must not destroy or replace an adopted network.
  `infra/README.md` gives the procedure.

## Forward Domain

The provider supports it. A UniFi Forward Domain is an NS record, and
`unifi_dns_record` accepts `record_type = "NS"` since provider v0.53.0
(issue #318, PR #319).

One detail is not verified. The UniFi UI asks for the IP address of the DNS
server, and the provider example uses a host name. The `dns` unit sends the VIP
address. Compare the first plan with a Forward Domain that you make by hand.

## Not in scope yet

- WLANs, firewall zones and policies, port profiles.
- Talos node entries. They go in `hosts` with `role = "talos"` when the
  cluster starts.
- The state backend stays open (decision 0005). `root.hcl` uses a local backend
  until then.
