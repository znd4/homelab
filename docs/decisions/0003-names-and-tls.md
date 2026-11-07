# 0003: Service names and TLS

**Status:** accepted for now, revisit · 2026-11

## Decision

- Services are named `<service>.<host>.internal`, e.g. `printer.hl01.internal`.
  `.internal` is ICANN-reserved for private use, so it can't collide with a
  real TLD.
- Caddy terminates TLS with **`tls internal`**, its own local CA. Admin devices
  trust that root CA once.
- DNS records live in UniFi, one A record per service, by clickops for now and
  later with Tofu `for_each`.

## Why not a wildcard record

UniFi's local DNS (Policy Table) offers A/AAAA/CNAME/SRV/Forward Domain, and
there is no evidence that wildcards work. That isn't verified, so it's worth
trying (`dig foo.hl01.internal @<gateway>`). If they don't work:

- Short term: one record per service. There are only a handful.
- If that becomes tedious: a **Forward Domain** record for `hl01.internal`
  pointing at a resolver on the host (CoreDNS or dnsmasq answering
  `*.hl01.internal`). Or generate the records from the flake, e.g. read
  `homelab.reverseProxy.vhosts` with `nix eval` and feed it to Tofu.

## The better option later: a real domain

A real domain with DNS-01 (e.g. `printer.hl01.home.<mydomain>`, Cloudflare)
gets certificates every device trusts with no CA installs. That matters for
phones, which make installing a custom CA painful.

- **Cost:** a domain, a scoped Cloudflare token (a secret, so it needs sops-nix
  first), and a Caddy build with the DNS plugin
  (`pkgs.caddy.withPlugins`).
- **Switching** is a change in `reverse-proxy.nix` only, because service
  modules only name their subdomain.

`tls internal` is enough for now because the only Caddy-fronted UI is the CUPS
admin page, which only I use. Revisit when the first service that phones or
family use needs a web UI.
