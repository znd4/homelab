# Unit: DHCP reservations from inventory.hosts. The networks must exist first.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/infra/catalog/modules/clients"
}

dependencies {
  paths = [values.networks_path]
}

inputs = {
  site     = values.site
  hosts    = include.root.locals.inventory.hosts
  networks = include.root.locals.inventory.networks
}
