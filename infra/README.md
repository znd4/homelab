# infra

OpenTofu + Terragrunt for things outside NixOS. Not started yet. The state
backend has to be decided first; see
[decision 0005](../docs/decisions/0005-tofu-state-backend.md).

Planned layout:

```
infra/
  root.hcl                 remote_state (S3/R2), encryption, provider defaults
  network/unifi/           ubiquiti-community/unifi: networks, WLANs, fixed IPs, DNS records, firewall zones
  talos/                   later
```

UniFi provider notes (as of v0.65, 2026-11):
- Published on the OpenTofu registry as `ubiquiti-community/unifi`.
- Supports API-key auth (`UNIFI_API_KEY`). Built against UniFi Network 10.6.
- `unifi_dns_record` covers static DNS, and `unifi_client` covers fixed IPs and
  per-client local DNS.
- Bring in the existing clickops config with `import` blocks rather than
  recreating it.
