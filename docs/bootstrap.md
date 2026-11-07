# Bootstrapping a NixOS host

Example: `hl01`. For a new host, copy `nix/hosts/hl01`, change the hostname,
and add it to `nixosConfigurations` and the CI matrix.

## 0. Once per repo

Put your admin public key(s) in `nix/keys.nix`. With the 1Password agent:
`ssh-add -L`, or copy it from the 1Password item. The build fails until at
least one key is present.

## 1. Installer USB

```sh
nix build .#installer-iso     # needs an x86_64-linux builder
# or download the `homelab-installer-iso` artifact from the latest CI run
sudo dd if=result/iso/*.iso of=/dev/diskN bs=4M status=progress   # macOS: diskutil list; use /dev/rdiskN
```

Boot the target from it. It gets a DHCP address, announces itself as
`nixos-installer.local`, and accepts your key as root.

## 2. Inspect the hardware

```sh
ssh root@nixos-installer.local
ls -l /dev/disk/by-id/            # pick the install disk
nixos-facter > /tmp/facter.json
```

On your workstation:

```sh
scp root@nixos-installer.local:/tmp/facter.json nix/hosts/hl01/facter.json
# set disko.devices.disk.main.device in nix/hosts/hl01/disko.nix to the by-id path
git add nix/hosts/hl01      # flakes ignore untracked files
```

`facter.json` replaces `hardware-configuration.nix`. It also tells the
remote-unlock initrd which NIC driver to load.

## 3. Secrets for the install

```sh
tmp=$(mktemp -d)
# Dedicated initrd SSH host key. It is stored unencrypted on the ESP, so it is not the real host key.
# Everything under $tmp/files is copied onto the new root filesystem.
install -d -m700 "$tmp/files/etc/secrets/initrd"
ssh-keygen -t ed25519 -N "" -C "hl01-initrd" -f "$tmp/files/etc/secrets/initrd/ssh_host_ed25519_key"

# LUKS passphrase: create a 1Password item first, e.g. "hl01 LUKS".
op read "op://Homelab/hl01 LUKS/password" | tr -d '\n' > "$tmp/luks.key"   # no trailing newline
```

## 4. Install

```sh
nix develop -c nixos-anywhere \
  --flake .#hl01 \
  --disk-encryption-keys /tmp/secret.key "$tmp/luks.key" \
  --extra-files "$tmp/files" \
  --build-on remote \
  root@nixos-installer.local
```

Delete `$tmp` afterwards: `rm -rf "$tmp"`.

nixos-anywhere partitions the disk with disko (the passphrase from
`/tmp/secret.key`), installs, and reboots. `--build-on remote` builds on the target, so a Mac
workstation doesn't need a Linux builder.

## 5. First boot: unlock

In UniFi, give hl01 a fixed IP (DHCP reservation). The initrd has no mDNS, so
unlock by IP:

```sh
ssh -p 2222 root@<hl01-ip>      # answers the LUKS prompt, then disconnects
```

Add the initrd key to known_hosts under its own alias so it never collides
with the real host key:

```
Host hl01-unlock
  HostName <hl01-ip>
  Port 2222
  User root
  HostKeyAlias hl01-initrd
```

## 6. Network and TLS (clickops for now)

- UniFi → Settings → Policy Table → DNS: A record `printer.hl01.internal` →
  hl01 IP. UniFi doesn't appear to support wildcard records, so add one record
  per service (see decision 0003).
- Trust Caddy's local CA on your admin devices:
  `ssh znd4@hl01.local sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`
  On macOS, add it to Keychain Access and mark it "Always Trust".
- Printing needs none of this. Clients find the printer over mDNS.

## 7. Day-2 deploys

```sh
nixos-rebuild switch --flake .#hl01 \
  --target-host znd4@hl01.local --build-host znd4@hl01.local --sudo
```
