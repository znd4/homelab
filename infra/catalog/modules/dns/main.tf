# UniFi "Forward Domain" for the homelab zone: the gateway sends queries for
# `domain` to the homelab DNS VIP. All other names still resolve through the
# gateway.
#
# The provider has no separate forward resource. In UniFi a Forward Domain
# entry is an NS record, and the provider manages it with
# unifi_dns_record, record_type = "NS" (provider issue #318, PR #319,
# changelog v0.53.0).

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

variable "domain" {
  description = "The zone to forward, for example home.znd4.dev."
  type        = string
}

variable "dns_vip" {
  description = "The IPv4 address of the homelab DNS service (inventory.vips.dns)."
  type        = string
}

resource "unifi_dns_record" "forward" {
  site        = var.site
  name        = var.domain
  record_type = "NS"
  # The UniFi UI asks for the IP address of the DNS server. The provider
  # example uses a host name. Check the first plan against a Forward Domain
  # that you make by hand.
  value = var.dns_vip
}
