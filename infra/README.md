# infra

OpenTofu + Terragrunt for things outside NixOS. Not started yet. Decide the
state backend first. See [decision 0005](../docs/decisions/0005-tofu-state-backend.md).

Planned layout:

```
infra/
  root.hcl                 remote_state (S3/R2), encryption, provider defaults
  network/unifi/           ubiquiti-community/unifi: networks, WLANs, fixed IPs, Forward Domain, firewall zones
  talos/                   later
```

The homelab DNS service holds the `home.znd4.dev` records, and the flake makes
them (decision 0006). UniFi needs only the Forward Domain rule and the DHCP
reservations.

UniFi provider notes (as of v0.65, 2026-11):

- The OpenTofu registry has it as `ubiquiti-community/unifi`.
- It supports API-key auth (`UNIFI_API_KEY`). Its SDK targets UniFi Network 10.6.
- `unifi_client` covers fixed IPs. `unifi_dns_record` covers static DNS.
- Bring in the current hand-made config with `import` blocks. Do not make it again.
