# 0003: Service names and TLS

**Status:** accepted · 2026-11

## Decision

- Each service has the name `<service>.home.znd4.dev`, for example
  `printer.home.znd4.dev`. The name does not include the host.
- Caddy uses one wildcard certificate, `*.home.znd4.dev`, from Let's Encrypt.
- Caddy gets the certificate with a DNS-01 challenge in a separate deSEC zone.
- No public A records exist for these names (split-horizon DNS). The homelab
  DNS service answers for them on the LAN (decision 0006).

## Names without the host

A service can move to another NixOS host or to Kubernetes. Its name stays the
same, so bookmarks and client config stay correct. Only the DNS record changes.

`homelab.domain` is `home.znd4.dev` for every host. A service module sets only
its subdomain.

## One wildcard certificate

Every public certificate goes into the Certificate Transparency logs, and
anyone can read them. With one certificate per service, the logs show the name
of each service. With one wildcard certificate, the logs show only
`*.home.znd4.dev`.

Caddy serves one site, `*.home.znd4.dev`. Each service is a `host` matcher in
that site (see `nix/modules/reverse-proxy.nix`).

## DNS-01 through a CNAME

Let's Encrypt cannot connect to a LAN-only host. DNS-01 needs no inbound
connection. Wildcard certificates also require DNS-01.

`znd4.dev` is at DNSimple. A DNSimple token can change every record in the
zone, including MX, SPF and DKIM. A person with that token can receive the
mail for the domain. Password resets go to that mail, so the risk is high.
Scoped DNSimple tokens exist, but only on some plans.

So the token never goes on a homelab host:

1. A permanent CNAME in `znd4.dev` points `_acme-challenge.home.znd4.dev` at a
   name in a deSEC zone, for example `_acme-challenge.znd4-homelab.dedyn.io`.
2. Let's Encrypt follows the CNAME.
3. Caddy writes the TXT record in deSEC. The Caddy option
   `dns_challenge_override_domain` sets the deSEC name.
4. The host has only a deSEC token, from sops (decision 0007).

The deSEC token can change only the deSEC zone. The DNSimple credentials stay
on the workstation.

## No public records

Public DNS has no A records for `*.home.znd4.dev`. The UniFi gateway forwards
the zone to the homelab DNS service.

Some clients do not use the gateway for DNS. Examples are Android Private DNS
and browsers with DNS over HTTPS. These clients cannot resolve homelab names.

If that becomes a problem, add public A records with the private IPs. They
show only internal addresses, which have little value to an attacker.

## Other notes

- `.dev` is on the HSTS preload list. Browsers use only HTTPS for every
  `*.znd4.dev` name. Caddy serves HTTPS, so this has no effect.
- `homelab.reverseProxy.tls = "internal"` stays as an option. Caddy then uses
  its local CA, and clients must trust the Caddy root certificate. Use it for
  tests, or if DNS-01 is not available.
