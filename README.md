# homelab

Config for my homelab: NixOS on bare metal today, Kubernetes on Talos later,
and network config as code eventually.

## Layout

```
flake.nix                 hosts, installer ISO, dev shell
nix/
  keys.nix                admin SSH public keys (used everywhere)
  installer.nix           bootstrap ISO for nixos-anywhere installs
  modules/                custom NixOS modules, all under `homelab.*`
    base.nix              users, sshd, firewall, nix settings, mDNS
    remote-unlock.nix     SSH in initrd for LUKS unlock (on by default)
    reverse-proxy.nix     Caddy vhosts at <service>.<host>.internal
    services/cups.nix     LAN print server
  hosts/<host>/           per-machine config: disko layout, facter report, services
infra/                    OpenTofu + Terragrunt (not started; see infra/README.md)
docs/
  architecture.md         where this is going
  bootstrap.md            runbook: install a new NixOS host
  decisions/              short decision records, with the open questions
```

## Common commands

```sh
nix develop                                    # nixos-anywhere, nixos-rebuild, tofu, terragrunt
nix build .#installer-iso                      # bootstrap USB image (needs a Linux builder, or download it from CI)
nixos-rebuild switch --flake .#hl01 \
  --target-host znd4@hl01.local --build-host znd4@hl01.local --sudo
nixos-rebuild build-image --flake .#hl01 --image-variant qemu-efi   # host as a VM image
```

## Hosts

| Host | Role | Services |
| --- | --- | --- |
| hl01 | First NixOS box; runs services until the cluster exists | CUPS (`printer.hl01.internal`) |
