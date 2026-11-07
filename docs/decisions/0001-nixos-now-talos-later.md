# 0001: NixOS on bare metal now, Talos for Kubernetes later

**Status:** accepted · 2026-11

## Decision

- Bare-metal hosts that aren't Kubernetes nodes run NixOS, configured from this
  flake with custom modules under `homelab.*`.
- Kubernetes nodes will run Talos.
- Services start on NixOS and move to the cluster once it exists.

## Why

- **Getting something useful running now.** The printer is the first real
  workload, and one NixOS box gets it running quickly.
- **NixOS modules are a good holding pattern.** Each service is a few dozen
  declarative lines, and the cutover to Kubernetes is per service.
- **Talos for the nodes** because the OS is immutable and API-only, so nothing
  drifts and there is no SSH. It is managed the same way from here (machine
  configs as code).

## Notes

- Some things may never move to Kubernetes: hardware-bound services (USB), and
  things the cluster depends on (DNS, a bootstrap/admin host).
- Images are built with the image builder built into nixpkgs (25.05+), which
  replaced the archived nixos-generators:
  - `nixos-rebuild build-image --image-variant <v>`
  - `config.system.build.images.<v>`

  We use it in two ways:
  - The **bootstrap ISO** (`.#installer-iso`) is a minimal installer with our
    keys. Hosts are then installed with nixos-anywhere + disko, so disk layout
    and encryption are declarative too.
  - **Per-host images** (`qemu-efi`, `raw-efi`, `iso`) work from any host
    config, e.g. to test hl01 in a VM before touching hardware.
