# DHCP reservations (fixed IPs) for the hosts in nix/inventory.nix.
#
# `allow_existing = true` takes over a client that UniFi already knows, for
# example a host with a reservation made by hand. A host without a MAC
# address is skipped until the bootstrap procedure records its MAC.

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "~> 0.65.0"
    }
  }
}

variable "site" {
  type    = string
  default = "default"
}

variable "hosts" {
  description = "inventory.hosts from nix/inventory.nix."
  type = map(object({
    role    = string
    network = string
    mac     = optional(string)
    ip      = string
  }))
}

variable "networks" {
  description = "inventory.networks from nix/inventory.nix. Only `subnet` is used, to check each host IP."
  type = map(object({
    subnet = string
  }))
}

locals {
  with_mac = { for name, h in var.hosts : name => h if h.mac != null }
}

resource "unifi_client" "this" {
  for_each = local.with_mac

  site     = var.site
  mac      = lower(each.value.mac)
  name     = each.key
  fixed_ip = each.value.ip
  note     = "Managed by znd4/homelab infra (role: ${each.value.role})"

  allow_existing         = true
  skip_forget_on_destroy = true

  lifecycle {
    precondition {
      condition     = contains(keys(var.networks), each.value.network)
      error_message = "Host ${each.key} names the network ${each.value.network}, which is not in the inventory."
    }
    precondition {
      condition     = cidrcontains(var.networks[each.value.network].subnet, each.value.ip)
      error_message = "The IP of host ${each.key} is not inside the subnet of network ${each.value.network}."
    }
  }
}

output "skipped_hosts" {
  description = "Hosts without a MAC address. They get no reservation yet."
  value       = sort([for name, h in var.hosts : name if h.mac == null])
}
