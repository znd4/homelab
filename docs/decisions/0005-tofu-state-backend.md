# 0005: OpenTofu state backend

**Status:** proposed · 2026-11. Network stays clickops until this decision is final.

## Proposal

**Cloudflare R2 via the S3 backend**, with native locking and client-side state
encryption. Move to Ceph RGW once the cluster has it.

```hcl
# root.hcl (Terragrunt)
remote_state {
  backend = "s3"
  generate = { path = "backend.tf", if_exists = "overwrite" }
  config = {
    bucket       = "znd4-homelab-tofu"
    key          = "${path_relative_to_include()}/tofu.tfstate"
    region       = "auto"
    endpoints    = { s3 = "https://<account>.r2.cloudflarestorage.com" }
    use_lockfile = true          # S3 conditional writes; no DynamoDB needed
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_metadata_api_check     = true
  }
}
```

Plus `encryption` with the `pbkdf2` key provider (passphrase via
`TF_ENCRYPTION` / 1Password), `aes_gcm`, and `enforced = true`. State holds
UniFi credentials and WLAN PSKs, so it should be unreadable to the bucket host.

## Why R2 over the alternatives

| Option | Notes |
| --- | --- |
| **R2** | Free tier covers this easily. Documents atomic `If-None-Match` PUTs, so `use_lockfile` works. No AWS account to secure. |
| AWS S3 | Works fine, but means another account to lock down (root MFA, IAM, budget alarms) for a few KB of state. |
| Local MinIO/Garage | Chicken and egg: the state for the network lives on a box that needs the network. The MinIO community edition is effectively no longer developed. Garage's conditional-write support is not verified. |
| `pg` / HTTP backends | Need a database or GitLab first. |
| Local file + git | No locking. Encryption makes committing possible, but it's easy to clobber state. |

## Migration to Ceph RGW later

1. Check that RGW does conditional PUTs. A second `PUT` with
   `If-None-Match: *` must return 412. Squid 19.2.1+ or Tentacle. There was an
   earlier bug on versioned buckets.
2. Point the Terragrunt `remote_state` at RGW.
3. Re-init each unit with `-migrate-state` (`tofu init -migrate-state` through Terragrunt).
4. Keep the same encryption passphrase.

Even then, keep a copy of network state off-cluster, because the cluster
depends on the network.

## Terragrunt scope

Start with a single `infra/network/unifi` unit. Terragrunt earns its place once
there are several units (Talos, Cloudflare DNS, possibly R2 itself) sharing
backend and provider config.
