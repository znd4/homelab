# Unit: UniFi networks from inventory.networks.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/infra/catalog/modules/networks"
}

inputs = {
  site     = values.site
  networks = include.root.locals.inventory.networks
}
