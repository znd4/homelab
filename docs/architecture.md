# Architecture

## End state

- **Kubernetes on Talos** runs most workloads. Talos is immutable and
  API-driven, with no SSH and no package manager, so the nodes are cattle.
- **NixOS on bare metal** runs whatever is a poor fit for Kubernetes:
  - things the cluster depends on (DNS, possibly storage at first, the
    Tofu/Talos tooling host);
  - hardware-bound services (USB printers, a possible Zigbee or Z-Wave
    coordinator);
  - anything simpler as a systemd unit than as a Helm chart.
- **The network (UniFi) is managed as code** with OpenTofu + Terragrunt via
  `ubiquiti-community/unifi`: networks, WLANs, fixed IPs, DNS records, firewall
  zones.
- **Storage:** eventually Ceph (Rook). Its RGW also becomes the Tofu state
  backend (see [decision 0005](decisions/0005-tofu-state-backend.md)).

## Phases

1. **First NixOS host (`hl01`)** ← now
   - [x] Custom modules: `base`, `remote-unlock`, `reverse-proxy`, `services/cups`
   - [x] Installer ISO, disko layout, CI builds
   - [ ] Add an SSH key to `nix/keys.nix`, then install on real hardware ([bootstrap.md](bootstrap.md))
   - [ ] UniFi (clickops): DHCP reservation for hl01, DNS record `printer.hl01.internal`
   - [ ] Declare the printer in `hardware.printers.ensurePrinters`
2. **Network as code**
   - Tofu state backend, then import the existing UniFi config
   - Manage DNS records with `for_each` over each host's services
3. **Talos cluster**
   - Talos machine configs generated from this repo (`talhelper` or the Talos Tofu provider)
   - Flux or Argo CD for workloads
4. **Migrate workloads** from NixOS hosts to the cluster, service by service.
   NixOS modules stay as the fallback.

## Conventions

- Every custom option lives under `homelab.*`. Service modules are
  `homelab.services.<name>`, off by default, and a host enables them.
- A service with a web UI registers `homelab.reverseProxy.vhosts.<sub>` rather
  than configuring Caddy itself. It is served at `<sub>.<host>.internal`.
- Things a host must not forget, such as an SSH key or initrd NIC drivers, are
  enforced with `assertions`. Never leave them as silent defaults.
- Secrets: none yet. The first service that needs one brings in sops-nix,
  keyed to each host's SSH host key. See open questions.

## Open questions

- Hostname scheme (`hl01` is a placeholder).
- Secrets tool: sops-nix or agenix. Leaning sops-nix, because the same
  age/SOPS files can feed Tofu (`carlpett/sops`) and Kubernetes (SOPS in Flux).
- Real domain vs `.internal` ([decision 0003](decisions/0003-names-and-tls.md)).
