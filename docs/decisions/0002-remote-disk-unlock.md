# 0002: Full-disk encryption with SSH unlock on every NixOS host

**Status:** accepted · 2026-11

## Decision

- Every NixOS host's root is LUKS2 (disko), unlocked by passphrase.
- `homelab.remoteUnlock` is a module in `nix/modules/` that **defaults to
  enabled**, so every host gets it without opting in. It runs sshd in the
  systemd initrd on port 2222.

## Details

- **systemd initrd** (`boot.initrd.systemd.enable`) with `systemd-networkd`
  doing DHCP. `cryptsetup-askpass` doesn't exist under systemd initrd.
  Authorized keys get a forced command,
  `systemd-tty-ask-password-agent --watch`, so a login can only answer the
  passphrase prompt and gets no shell.
- **The forced command needs a terminal** (`ssh -t`). Without one, the agent
  reads EOF and sends an empty passphrase for each new prompt. It also keeps
  running after the client disconnects, so it blocks every later attempt. The
  VM test found this. On a terminal, a disconnect sends SIGHUP and the agent
  stops.
- **Unlimited tries** (`tries=0` on every LUKS device). Each closed session
  counts as one attempt. With the systemd default of 3 tries, failed attempts
  put the host in emergency mode, which works only on the local console.
  Only a holder of an admin SSH key can make an attempt.
- **Test:** `nix build .#checks.x86_64-linux.remote-unlock-vm` boots a VM from
  a LUKS disk through systemd-boot and unlocks it over SSH. It does not test
  the `en*` interface match or the facter NIC drivers.
- **NIC drivers** come from the host's nixos-facter report (upstream
  `hardware.facter`). It adds network modules to the initrd whenever
  `boot.initrd.network.enable` is true.
- **Host key:** a dedicated key at `/etc/secrets/initrd/ssh_host_ed25519_key`.
  The bootstrap procedure makes it, and `nixos-anywhere --extra-files` copies it.
  - It ends up in the initrd on the **unencrypted** ESP, so anyone with
    physical access can read it and spoof the prompt. That's why it is never
    the real host key and gets its own known_hosts alias.
  - Accepted risk: someone who can plant a fake unlock prompt on the box has
    physical access anyway.

## Not done (maybe later)

- **TPM2 auto-unlock** (`systemd-cryptenroll --tpm2-pcrs=7`) as the normal
  path, keeping SSH as the fallback. It means unattended reboots, but only
  limited protection against someone who steals the whole machine.
- **Unlock over Tailscale/WireGuard** from outside the LAN. nixpkgs has no
  module for it, and the node identity would sit on the ESP. Plain WireGuard is
  the simpler option if needed.
- **Clevis/Tang** network-bound unlock (auto-unlock only while on the home
  LAN). Worth looking at once there are several hosts.
