# Shared Terragrunt config. Every unit includes it.
#
# - inventory: the address plan from nix/inventory.nix, read with `nix eval`.
#   The flake sees only files that git tracks.
# - provider: ubiquiti-community/unifi. Auth comes from the environment
#   (UNIFI_API, UNIFI_API_KEY). See infra/README.md.
# - state: encrypted with a passphrase (TF_VAR_state_passphrase). The backend is
#   "local" by default. HOMELAB_TOFU_BACKEND=s3 selects the R2 bucket from
#   decision 0005.

locals {
  repo_root = get_repo_root()
  inventory = jsondecode(run_cmd("--terragrunt-quiet", "nix", "eval", "--json", "${local.repo_root}#inventory"))

  backend = get_env("HOMELAB_TOFU_BACKEND", "local")
  # State path per unit, without the generated `.terragrunt-stack/` part.
  state_key = replace(path_relative_to_include(), ".terragrunt-stack/", "")

  backend_configs = {
    local = {
      path = "${get_parent_terragrunt_dir()}/.state/${local.state_key}/tofu.tfstate"
    }
    # Decision 0005 (proposed): Cloudflare R2 through the S3 backend.
    s3 = {
      # TODO(tofu-backend): make the bucket, then set the name and account ID.
      bucket       = "znd4-homelab-tofu"
      key          = "${local.state_key}/tofu.tfstate"
      region       = "auto"
      endpoints    = { s3 = "https://ACCOUNT_ID.r2.cloudflarestorage.com" }
      use_lockfile = true

      use_path_style              = true
      skip_credentials_validation = true
      skip_region_validation      = true
      skip_requesting_account_id  = true
      skip_s3_checksum            = true
      skip_metadata_api_check     = true

      # Terragrunt-only keys: do not try to make or change the bucket with AWS APIs.
      disable_bucket_update  = true
      skip_bucket_versioning = true
    }
  }
}

remote_state {
  backend = local.backend
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = local.backend_configs[local.backend]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    # Reads UNIFI_API and UNIFI_API_KEY from the environment.
    provider "unifi" {}
  EOF
}

generate "encryption" {
  path      = "encryption.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    variable "state_passphrase" {
      description = "Passphrase for OpenTofu state and plan encryption. Set TF_VAR_state_passphrase."
      type        = string
      sensitive   = true
    }

    terraform {
      encryption {
        key_provider "pbkdf2" "main" {
          passphrase = var.state_passphrase
        }
        method "aes_gcm" "main" {
          keys = key_provider.pbkdf2.main
        }
        state {
          method   = method.aes_gcm.main
          enforced = true
        }
        plan {
          method   = method.aes_gcm.main
          enforced = true
        }
      }
    }
  EOF
}
