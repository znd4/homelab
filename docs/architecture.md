# Architecture

## End state

- **Kubernetes on Talos** runs most workloads. Talos is immutable and has only
  an API. It has no SSH and no package manager, so a node is easy to replace.
- **NixOS on bare metal** runs the things that do not fit Kubernetes well:
  - services that the cluster depends on, such as DNS and the admin host.
  - services that need local hardware, such as USB printers or a Zigbee
    coordinator.
  - services that are simpler as a systemd unit than as a Helm chart.
- **OpenTofu and Terragrunt manage the UniFi network** with the
  `ubiquiti-community/unifi` provider. This covers networks, WLANs, fixed IPs,
  the DNS forward and firewall zones.
- **Ceph (Rook) supplies storage** later. Its RGW also becomes the Tofu state
  backend (decision 0005).

## Phases

1. **First NixOS host (`hl01`).** This is the current phase.
   - [x] Modules: `base`, `remote-unlock`, `reverse-proxy`, `services/cups`, `services/dns`
   - [x] Installer ISO, disko layout, sops-nix, deploy-rs, CI builds
   - [ ] Do the bootstrap procedure on real hardware ([bootstrap.md](bootstrap.md))
   - [ ] UniFi: servers network, DHCP reservation, Forward Domain for
     `home.znd4.dev`. Do it by hand, or apply the Terragrunt stack (phase 3).
   - [ ] Declare the printer in `hardware.printers.ensurePrinters`
2. **A second DNS host.** It removes the single point of failure for
   `home.znd4.dev` (decision 0006).
3. **Network as code** (decision 0008).
   - [x] `nix/inventory.nix` as the single source of truth for addresses
   - [x] Terragrunt stack `infra/live/home`: units `networks`, `clients`, `dns`
   - [ ] Choose the state backend (decision 0005)
   - [ ] Adopt the current UniFi config: first `plan` with no destroy, then `apply`
   - [ ] Later: WLANs, firewall zones and policies
4. **Talos cluster.**
   - Make the Talos machine configs from this repository (`talhelper` or the
     Talos Tofu provider).
   - Use Flux or Argo CD for workloads.
5. **Move workloads** from NixOS hosts to the cluster, one service at a time.
   The NixOS modules stay as the fallback.

## Conventions

- Every custom option is below `homelab.*`. Service modules are
  `homelab.services.<name>`. They are off by default, and a host enables them.
- A service with a web UI adds `homelab.reverseProxy.vhosts.<sub>`. It does
  not configure Caddy directly. Caddy serves it at `<sub>.home.znd4.dev`.
- Addresses come from `nix/inventory.nix` (decision 0008). Do not write an
  address in a host file or in HCL.
- Networks follow trust zones. Server classes get address ranges in the
  servers network, not their own subnets.
- DNS records come from the flake (decision 0006). Do not add records by hand
  in UniFi.
- A host must not forget some values, such as an SSH key or a NIC driver.
  Modules check these values with `assertions`.
- Secrets use sops-nix (decision 0007).
- Deploys use deploy-rs (`deploy .#<host>`).

## Decisions

| # | Title |
| --- | --- |
| [0001](decisions/0001-nixos-now-talos-later.md) | NixOS on bare metal now, Talos later |
| [0002](decisions/0002-remote-disk-unlock.md) | Full-disk encryption with SSH unlock |
| [0003](decisions/0003-names-and-tls.md) | Service names and TLS |
| [0004](decisions/0004-cups-exposure.md) | Exposure of the print server |
| [0005](decisions/0005-tofu-state-backend.md) | OpenTofu state backend (proposed) |
| [0006](decisions/0006-dns.md) | DNS for the homelab zone |
| [0007](decisions/0007-secrets.md) | Secrets with sops-nix |
| [0008](decisions/0008-network-as-code.md) | Network as code |

## Open questions

- Hostname scheme. `hl01` is a placeholder.
- The Tofu state backend (decision 0005).
