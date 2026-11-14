# 0007: Secrets with sops-nix

**Status:** accepted · 2026-11

## Decision

sops-nix with age keys manages host secrets. Each host has its own file,
`nix/hosts/<host>/secrets.yaml`, encrypted in git.

Each file has two recipients (see `.sops.yaml`):

- the admin age key. 1Password stores it. The workstation uses it to edit
  secrets.
- the host age key. `ssh-to-age` makes it from the host SSH key. The host uses
  it to decrypt its secrets at activation.

## Host keys before the install

The bootstrap procedure makes the host SSH key on the workstation, before the
install. So you can encrypt the secrets before the host exists.
`nixos-anywhere --extra-files` copies the key to the new system.
`docs/bootstrap.md` has the steps.

## Why sops-nix

- The same SOPS files can later supply OpenTofu (the `carlpett/sops`
  provider) and Kubernetes (SOPS support in Flux).
- One file holds many secrets, and the file is easy to edit.
- agenix also works. It has no Tofu or Flux support of the same kind.

## First secret

`desec-token`: the deSEC API token for the ACME DNS-01 challenge (decision
0003). sops-nix puts it in an environment file for Caddy.
