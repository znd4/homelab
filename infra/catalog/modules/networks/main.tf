# UniFi networks (VLANs) from nix/inventory.nix.
#
# A network with `adopt = true` already exists in UniFi. The import block
# takes it over by name, so tofu never makes it again. Check the first plan:
# it must show no destroy or replace for an adopted network.

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

variable "networks" {
  description = "inventory.networks from nix/inventory.nix. Extra attributes are ignored."
  type = map(object({
    name    = string
    adopt   = bool
    vlan    = optional(number)
    subnet  = string
    gateway = string
    dhcp = object({
      start = string
      stop  = string
    })
  }))

  validation {
    condition     = alltrue([for n in var.networks : cidrcontains(n.subnet, n.gateway)])
    error_message = "Each network gateway must be inside its subnet."
  }
  validation {
    condition = alltrue([
      for n in var.networks : cidrcontains(n.subnet, n.dhcp.start) && cidrcontains(n.subnet, n.dhcp.stop)
    ])
    error_message = "Each DHCP range must be inside its subnet."
  }
}

import {
  for_each = { for k, n in var.networks : k => n if n.adopt }
  to       = unifi_network.this[each.key]
  # The provider imports a network by name. See its docs for unifi_network.
  id = "name=${each.value.name}"
}

resource "unifi_network" "this" {
  for_each = var.networks

  site = var.site
  name = each.value.name
  vlan = each.value.vlan
  # The provider wants the gateway address with the prefix length, for example 10.0.20.1/24.
  subnet = "${each.value.gateway}/${split("/", each.value.subnet)[1]}"

  dhcp_server = {
    enabled = true
    start   = each.value.dhcp.start
    stop    = each.value.dhcp.stop
  }
}

output "network_ids" {
  description = "UniFi network IDs, by inventory key."
  value       = { for k, n in unifi_network.this : k => n.id }
}
