# infra

OpenTofu + Terragrunt for things outside NixOS. Today this is the UniFi
network. Decision 0008 explains the design.

## Layout

```
infra/
  root.hcl                       inventory, provider, state backend, state encryption
  catalog/
    modules/networks/            unifi_network per inventory network (adopts by name)
    modules/clients/             unifi_client fixed IP per inventory host
    modules/dns/                 Forward Domain for home.znd4.dev (NS record)
    units/<unit>/terragrunt.hcl  wiring from the inventory to a module
  live/home/terragrunt.stack.hcl the stack: networks, clients, dns
```

The addresses come from `nix/inventory.nix`. `root.hcl` reads them with
`nix eval --json <repo>#inventory`. Do not copy addresses into HCL.

The flake sees only files that git tracks. Run `git add` after you change
`nix/inventory.nix`, or Terragrunt reads the old values.

## Credentials

The provider reads these variables:

| Variable | Value |
| --- | --- |
| `UNIFI_API` | The controller URL, for example `https://192.168.1.1`. Do not add `/api`. |
| `UNIFI_API_KEY` | An API key from UniFi Network (Settings > Control Plane > Integrations). |
| `UNIFI_INSECURE` | `true` if the gateway uses its self-signed certificate. |
| `TF_VAR_state_passphrase` | The state encryption passphrase. Use 16 characters or more. |

Keep the values in 1Password, and load them with `op run`. Example `.env`
file with secret references (not secret values):

```sh
UNIFI_API=https://192.168.1.1
UNIFI_API_KEY=op://Homelab/UniFi API key/credential
TF_VAR_state_passphrase=op://Homelab/homelab tofu state/password
```

Then run each command through 1Password:

```sh
op run --env-file=infra/.env -- terragrunt stack run plan --working-dir infra/live/home
```

I did not check the UniFi menu name for API keys. It can be different in your
UniFi version.

## State backend

`HOMELAB_TOFU_BACKEND` selects the backend:

| Value | Backend |
| --- | --- |
| `local` (default) | `infra/.state/<unit>/tofu.tfstate`. Git ignores it. |
| `s3` | The R2 bucket from decision 0005. Fill the `TODO(tofu-backend)` values in `root.hcl` first. |

Both backends encrypt state and plans with `TF_VAR_state_passphrase`. If you
lose the passphrase, you cannot read the state.

To move from `local` to `s3`, run `init -migrate-state` in each unit with
`HOMELAB_TOFU_BACKEND=s3`. Use the same passphrase.

## First run: adopt the current network

You made the current UniFi config by hand. Tofu must adopt it, not make it again.

1. Set the real values of the default LAN in `nix/inventory.nix`
   (`networks.default`, with `adopt = true`).
2. For each other network that already exists in UniFi, set `adopt = true`
   and use its exact UniFi name.
3. Generate the stack:

   ```sh
   terragrunt stack generate --working-dir infra/live/home
   ```

4. Make a plan:

   ```sh
   op run --env-file=infra/.env -- terragrunt stack run plan --working-dir infra/live/home
   ```

5. Read the plan of the `networks` unit.

   WARNING: Do not apply a plan that destroys or replaces an adopted network.
   That disconnects all devices on it. Correct `nix/inventory.nix` and make a
   new plan.

6. Make sure that the adopted networks show only the changes that you want.
7. Apply:

   ```sh
   op run --env-file=infra/.env -- terragrunt stack run apply --working-dir infra/live/home
   ```

The `clients` unit takes over a known client with `allow_existing`. A host
without a MAC address in the inventory gets no reservation.

## Checks without a controller

These commands need no UniFi access:

```sh
terragrunt stack generate --working-dir infra/live/home
TF_VAR_state_passphrase=dummy-passphrase terragrunt run --all --working-dir infra/live/home -- validate
```

## Provider notes (v0.65.0, 2026-11)

- The OpenTofu registry has it as `ubiquiti-community/unifi`. The modules pin `~> 0.65.0`.
- `unifi_network` imports by name: `name=<network name>`.
- `unifi_dns_record` with `record_type = "NS"` is a UniFi Forward Domain
  (provider issue #318, PR #319).
- WLANs and firewall zones are not in the stack yet.
