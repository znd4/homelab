# homelab

Config for my homelab. NixOS runs on bare metal now. Kubernetes on Talos comes
later, and network config as code after that.

## Layout

```
flake.nix                 hosts, deploy-rs nodes, installer ISO, dev shell
.sops.yaml                sops recipients (admin key + host keys)
nix/
  keys.nix                admin SSH public keys
  installer.nix           bootstrap ISO for nixos-anywhere installs
  modules/                custom NixOS modules, all below `homelab.*`
    base.nix              users, sshd, firewall, nix settings, mDNS, sops
    remote-unlock.nix     SSH in the initrd for LUKS unlock (on by default)
    reverse-proxy.nix     Caddy, *.home.znd4.dev, wildcard cert via DNS-01
    services/cups.nix     LAN print server
    services/dns.nix      CoreDNS for home.znd4.dev, keepalived VIP
  hosts/<host>/           disko layout, facter report, secrets, services
infra/                    OpenTofu + Terragrunt (not started, see infra/README.md)
docs/
  architecture.md         the plan and the conventions
  bootstrap.md            procedure to install a new NixOS host
  decisions/              short decision records
```

## Common commands

```sh
nix develop                     # deploy, nixos-anywhere, sops, ssh-to-age, dig, tofu
deploy .#hl01                   # build on hl01 and activate, with rollback
sops nix/hosts/hl01/secrets.yaml
nix build .#installer-iso       # bootstrap USB image (needs a Linux builder, or get it from CI)
nixos-rebuild build-image --flake .#hl01 --image-variant qemu-efi   # hl01 as a VM image
nix build .#checks.x86_64-linux.dns-vm   # VM test: DNS, VIP failover, Caddy -> CUPS (needs KVM)
```

## Hosts

| Host | Role | Services |
| --- | --- | --- |
| hl01 | First NixOS host. It runs services until the cluster exists. | CUPS (`printer.home.znd4.dev`), DNS for `home.znd4.dev` |

The build fails until you set the bootstrap values. `docs/bootstrap.md`
lists them.
