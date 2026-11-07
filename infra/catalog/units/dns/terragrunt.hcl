# Unit: Forward Domain for the homelab zone to the DNS VIP.
# The VIP is in the servers network, so that network must exist first.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/infra/catalog/modules/dns"
}

dependencies {
  paths = [values.networks_path]
}

inputs = {
  site    = values.site
  domain  = include.root.locals.inventory.domain
  dns_vip = include.root.locals.inventory.vips.dns
}
