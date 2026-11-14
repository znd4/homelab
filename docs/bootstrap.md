# Bootstrap a NixOS host

This procedure installs the first host, `hl01`, on bare metal.

- Do [Prepare the admin keys](#prepare-the-admin-keys) and [Prepare the ACME challenge zone](#prepare-the-acme-challenge-zone)
  one time for the repository.
- The sections from [Make the installer USB](#make-the-installer-usb) to [Check the result](#check-the-result)
  install one host.
- [Deploy changes](#deploy-changes) applies later changes.
- [Add another host](#add-another-host) adds a different host.

Run all commands from the repository root, inside `nix develop`. The dev shell
supplies `nixos-anywhere`, `deploy`, `sops`, `age`, `ssh-to-age` and `dig`.

## Prepare the admin keys

Do this part one time for the repository.

1. Get your SSH public key. With the 1Password SSH agent, run `ssh-add -L`.
2. Add the public key to `admins` in `nix/keys.nix`.

   The build fails until `admins` has at least one key. This check prevents a
   host that you cannot log in to.

3. Make the admin age key:

   ```sh
   age-keygen -o admin-age.txt
   ```

4. Save the full contents of `admin-age.txt` in 1Password, for example as the
   item "homelab age key".
5. Copy the public key (the line that starts with `age1`) to the `&admin` entry
   in `.sops.yaml`.
6. Delete `admin-age.txt`.

To decrypt secrets later, put the key in the environment from 1Password:

```sh
export SOPS_AGE_KEY="$(op read 'op://Private/homelab age key/notesPlain')"
```

Change the `op://` path to the 1Password item that you made above.

## Prepare the ACME challenge zone

Caddy gets the `*.home.znd4.dev` certificate with a DNS-01 challenge. Caddy
writes the challenge record in the deSEC zone `acme.znd4.dev`, not in
`znd4.dev`. Decision 0003 gives the reason.

1. Make an account at <https://desec.io>.
2. In deSEC, add the domain `acme.znd4.dev`.

   I did not check that deSEC accepts a subdomain whose parent zone is at
   another provider. If deSEC refuses it, stop and read decision 0003.

3. Add the records in the `znd4.dev` zone at DNSimple. The Pulumi program in
   `znd4/cloud` (`dnsimple/main.go`) manages them.

   | Name | Type | Content |
   | --- | --- | --- |
   | `acme` | NS | `ns1.desec.io` |
   | `acme` | NS | `ns2.desec.org` |
   | `_acme-challenge.home` | CNAME | `_acme-challenge.acme.znd4.dev` |

4. Make sure that the delegation works:

   ```sh
   dig +short NS acme.znd4.dev
   ```

   The output must show the two deSEC name servers.

5. In the deSEC web interface, make a token with the name `homelab-login`.
   Give it the "manage tokens" permission. Set `LOGIN` to this token.
6. Make the token for Caddy. Set `TID` to the `id` in the output. Save the
   `token` value in 1Password. deSEC shows the value one time only.

   ```sh
   curl -sS https://desec.io/api/v1/auth/tokens/ \
     -H "Authorization: Token $LOGIN" -H "Content-Type: application/json" \
     -d '{"name": "hl01-acme"}'
   ```

7. Take away all write permissions from the Caddy token. deSEC requires this
   default policy before a specific policy.

   ```sh
   curl -sS https://desec.io/api/v1/auth/tokens/$TID/policies/rrsets/ \
     -H "Authorization: Token $LOGIN" -H "Content-Type: application/json" \
     -d '{"domain": null, "subname": null, "type": null}'
   ```

8. Let the Caddy token write only the challenge TXT record:

   ```sh
   curl -sS https://desec.io/api/v1/auth/tokens/$TID/policies/rrsets/ \
     -H "Authorization: Token $LOGIN" -H "Content-Type: application/json" \
     -d '{"domain": "acme.znd4.dev", "subname": "_acme-challenge", "type": "TXT", "perm_write": true}'
   ```

9. Delete the `homelab-login` token in the deSEC web interface.

The Caddy token can read all records in the deSEC account. It cannot read
or change `znd4.dev`. [Make the host keys and secrets](#make-the-host-keys-and-secrets) puts the Caddy token in the host secrets.

## Make the installer USB

1. Build the installer ISO. This step needs an x86_64-linux builder.

   ```sh
   nix build .#installer-iso
   ```

   As an alternative, download the `homelab-installer-iso` artifact from the
   latest CI run.

2. Find the USB device. On macOS, run `diskutil list`.

   WARNING: `dd` overwrites the device that you give it. Make sure that the
   device is the USB stick before you continue.

3. Write the ISO to the USB stick. On macOS, use `/dev/rdiskN`:

   ```sh
   sudo dd if=result/iso/<file>.iso of=/dev/rdiskN bs=4m
   ```

4. Boot the target machine from the USB stick.

The installer gets an address from DHCP. It announces itself as
`nixos-installer.local`. It accepts the keys in `nix/keys.nix` for `root`.

## Get the hardware facts

1. Log in to the installer:

   ```sh
   ssh root@nixos-installer.local
   ```

2. Write the hardware report:

   ```sh
   nixos-facter -o /tmp/facter.json
   ```

3. Find the install disk. Record its `/dev/disk/by-id/...` path:

   ```sh
   ls -l /dev/disk/by-id/
   ```

4. Find the LAN interface name, for example `enp1s0`:

   ```sh
   ip -br link
   ```

5. Find the MAC address of that interface. You need it for the DHCP
   reservation in [Set the network values](#set-the-network-values).
6. On your workstation, copy the report into the repository:

   ```sh
   scp root@nixos-installer.local:/tmp/facter.json nix/hosts/hl01/facter.json
   ```

The facter report replaces `hardware-configuration.nix`. It also tells the
remote-unlock initrd which NIC driver to load.

## Set the network values

`nix/inventory.nix` holds all addresses. NixOS and the Terragrunt units read
the same file. Decision 0008 explains the network plan.

1. Find all values that you must set:

   ```sh
   rg -n -F 'TODO(bootstrap)' nix .sops.yaml
   ```

2. In `nix/inventory.nix`, set `networks.default` to the real values of the
   current UniFi default LAN.
3. In `nix/inventory.nix`, set the VLAN IDs and subnets of the other networks.
   They must not overlap a current network.
4. In `nix/inventory.nix`, set `hosts.hl01.mac` to the MAC address from [Get the hardware facts](#get-the-hardware-facts).
5. Check that `hosts.hl01.ip` is in the `nixos` range of the servers network.
6. Check that `vips.dns` is in the `vips` range of the servers network.
7. Set the values in the host files:

   | File | Option | Value |
   | --- | --- | --- |
   | `nix/hosts/hl01/default.nix` | `homelab.services.dns.interface` | The interface from [Get the hardware facts](#get-the-hardware-facts) |
   | `nix/hosts/hl01/default.nix` | `homelab.reverseProxy.acme.challengeDomain` | The CNAME target from [Prepare the ACME challenge zone](#prepare-the-acme-challenge-zone) |
   | `nix/hosts/hl01/disko.nix` | `disko.devices.disk.main.device` | The by-id path from [Get the hardware facts](#get-the-hardware-facts) |

8. Make the servers network and the DHCP reservation in UniFi. Use one of
   these two methods:
   - By hand: in UniFi, make the servers network with the VLAN ID, subnet and
     DHCP range from `nix/inventory.nix`. Then make a DHCP reservation for
     the MAC address of hl01, with the address from `hosts.hl01.ip`.
   - With OpenTofu: do the procedure in `infra/README.md`. It makes the
     networks and the reservation from `nix/inventory.nix`.

9. Set the switch port of hl01 to the servers network (native VLAN).

   If the port stays on the default LAN, hl01 does not get the address from its DHCP reservation.

10. Turn on the UniFi mDNS proxy (multicast DNS) for the servers network and
    for the client networks.

    Without the mDNS proxy, clients in other networks do not find the printer.

## Make the host keys and secrets

The host SSH key decrypts the host's secrets. You make the key before the
install, so that you can encrypt the secrets first.

Both host keys go in 1Password. A reinstall then uses the same keys. The
secrets still decrypt, and `known_hosts` stays correct. The commands use the
vault `Homelab`. Change the vault name if you use a different vault.

1. Make a temporary directory. `nixos-anywhere` copies everything below
   `$tmp/files` to the root of the new system.

   ```sh
   tmp=$(mktemp -d)
   install -d -m755 "$tmp/files/etc/ssh"
   install -d -m700 "$tmp/files/etc/secrets/initrd"
   ```

2. Make the host SSH key in 1Password, and write it to `$tmp/files`:

   ```sh
   op item create --category "SSH Key" --ssh-generate-key ed25519 \
     --vault Homelab --title "hl01 host key" >/dev/null
   k="$tmp/files/etc/ssh/ssh_host_ed25519_key"
   op read "op://Homelab/hl01 host key/private key?ssh-format=openssh" > "$k"
   op read "op://Homelab/hl01 host key/public key" > "$k.pub"
   chmod 600 "$k"
   ```

3. Make the initrd SSH key in the same way. This key is different from the
   host key.

   The boot partition holds the initrd key without encryption.
   Never use the host key for the initrd.

   ```sh
   op item create --category "SSH Key" --ssh-generate-key ed25519 \
     --vault Homelab --title "hl01 initrd key" >/dev/null
   k="$tmp/files/etc/secrets/initrd/ssh_host_ed25519_key"
   op read "op://Homelab/hl01 initrd key/private key?ssh-format=openssh" > "$k"
   op read "op://Homelab/hl01 initrd key/public key" > "$k.pub"
   chmod 600 "$k"
   ```

4. Get the age public key of the host:

   ```sh
   op read "op://Homelab/hl01 host key/public key" | ssh-to-age
   ```

5. Copy the output to the `&hl01` entry in `.sops.yaml`.
6. Make the secrets file. Add the key `desec-token` with the deSEC token as the value:

   ```sh
   sops nix/hosts/hl01/secrets.yaml
   ```

7. Write the LUKS passphrase to a file. Make a 1Password item for it first,
   for example "hl01 LUKS".

   The file must not end with a newline. A newline becomes part of the passphrase.

   ```sh
   op read "op://Homelab/hl01 LUKS/password" | tr -d '\n' > "$tmp/luks.key"
   ```

8. Add the new files to git. A flake does not see files that git does not track.

   ```sh
   git add nix/hosts/hl01 .sops.yaml
   ```

## Install

WARNING: `nixos-anywhere` deletes all data on the disk in `disko.nix`. Make sure that the
device path is correct before you continue.

1. Run the install:

   ```sh
   nixos-anywhere \
     --flake .#hl01 \
     --disk-encryption-keys /tmp/secret.key "$tmp/luks.key" \
     --extra-files "$tmp/files" \
     --build-on remote \
     root@nixos-installer.local
   ```

2. Delete the temporary directory:

   ```sh
   rm -rf "$tmp"
   ```

`nixos-anywhere` uploads the passphrase to `/tmp/secret.key`. Disko reads
the passphrase from that file and formats the disk. Then `nixos-anywhere`
installs the system and reboots the machine. With `--build-on remote`, the
target builds the system, so a Mac workstation needs no Linux builder.

## Unlock the disk

The initrd has no mDNS. Use the IP address of the host.

1. Add this entry to `~/.ssh/config`. The alias keeps the initrd key apart
   from the host key in `known_hosts`.

   ```
   Host hl01-unlock
     HostName <hl01 lanAddress>
     Port 2222
     User root
     HostKeyAlias hl01-initrd
     RequestTTY yes
   ```

   The unlock prompt needs a terminal. Without one, the host prints
   `use ssh -t` and closes the connection.

2. Connect and type the passphrase:

   ```sh
   ssh hl01-unlock
   ```

The connection closes when the passphrase is correct. The boot then continues.

## Forward the homelab zone

If you used OpenTofu in [Set the network values](#set-the-network-values), the `dns` unit makes
the Forward Domain. Go to [Check the result](#check-the-result).

To make the Forward Domain by hand:

1. In UniFi Network, open Settings > Policy Table and add a DNS policy.
2. Set the type to Forward Domain.
3. Set the domain to `home.znd4.dev`.
4. Set the target to `vips.dns` from `nix/inventory.nix`.

I did not check the exact UniFi menu names. They can be different in your
UniFi version.

## Check the result

1. Check the DNS service through the VIP:

   ```sh
   dig +short TXT version.home.znd4.dev @<vip>
   ```

   The output is the git revision that you installed.

2. Check the gateway forward:

   ```sh
   dig +short printer.home.znd4.dev
   ```

   The output is the `lanAddress` of hl01.

3. Check HTTPS:

   ```sh
   curl -sI https://printer.home.znd4.dev
   ```

   The first certificate request can take a minute.

4. Print a test page from a laptop. The printer shows up through mDNS. It does
   not need the homelab DNS.

## Deploy changes

1. Commit the change.
2. Deploy it:

   ```sh
   nix develop -c deploy .#hl01
   ```

`deploy` builds on the target and activates the new system. If deploy-rs
cannot reach the host over SSH after the activation, deploy-rs restores the previous system.

When there is more than one DNS host, deploy one host at a time. Decision 0006
gives the order.

## Add another host

Do these steps first. Replace `<name>` with
the new host name.

1. Copy `nix/hosts/hl01` to `nix/hosts/<name>`.
2. Change `networking.hostName` in the new directory.
3. Add the host to `hosts` in `nix/inventory.nix`.
4. Add the name to `hostNames` in `flake.nix`.
5. Add the name to the CI matrix in `.github/workflows/build.yaml`.
6. Add a creation rule for the host to `.sops.yaml`.
7. Do the sections from [Make the installer USB](#make-the-installer-usb) to
   [Check the result](#check-the-result). Use `<name>` in place of `hl01` in each command.
   Skip [Forward the homelab zone](#forward-the-homelab-zone), which occurs one time only. If the
   installer USB still has the current admin keys, use it again.

If the new host also runs DNS, give it a lower `priority` than `hl01`.
Decision 0006 gives the details.
