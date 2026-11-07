# The home network: one UniFi site.
#
#   terragrunt stack generate      # writes .terragrunt-stack/ (not in git)
#   terragrunt stack run plan
#
# The units read addresses from nix/inventory.nix (through infra/root.hcl).
# The values here are only wiring.

locals {
  site = "default"
}

unit "networks" {
  source = "../../catalog/units/networks"
  path   = "networks"
  values = {
    site = local.site
  }
}

unit "clients" {
  source = "../../catalog/units/clients"
  path   = "clients"
  values = {
    site          = local.site
    networks_path = "../networks"
  }
}

unit "dns" {
  source = "../../catalog/units/dns"
  path   = "dns"
  values = {
    site          = local.site
    networks_path = "../networks"
  }
}
