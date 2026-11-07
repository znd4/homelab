# 0004: Exposure of the print server

**Status:** accepted · 2026-11

## Decision

| Path | Who | How |
| --- | --- | --- |
| Printing | Any LAN device | IPP straight to cupsd `:631`. Avahi advertises it as IPP Everywhere/AirPrint |
| Admin web UI | Me | `https://printer.home.znd4.dev` → Caddy → `localhost:631` |

## Why printing doesn't go through Caddy

- Clients find printers over mDNS, which advertises `hl01.local:631`, not our
  Caddy name. A proxy would also break IPP for many clients.
- Caddy adds nothing on that path. cupsd itself enforces LAN-only access
  (`allowFrom` = LAN CIDRs). The router never forwards port 631.

## Hardening

- cupsd answers only `localhost` + `homelab.reverseProxy.lanCidrs`.
  - Those CIDRs default to all of RFC1918.
  - TODO: narrow them to the actual VLANs once those exist (an IoT/guest VLAN
    shouldn't be able to print, or maybe it should).
- Caddy returns 403 to non-LAN sources and rewrites `Host: localhost`. CUPS
  rejects unknown Host headers to stop DNS rebinding, and requests from
  127.0.0.1 are only accepted with a localhost name.
- Admin operations still require a user in CUPS' `SystemGroup`
  (root/wheel/lpadmin) with a password.
  - `users.mutableUsers = false` and no admin password means this doesn't work
    out of the box.
  - That's intentional: **Nix declares the printer queues**
    (`hardware.printers.ensurePrinters`), and the web UI is for status and job
    management.
- `cups-browsed` is off. This host shares printers and doesn't discover other
  servers' queues, and cups-browsed has a recent CVE history (2024's remote
  RCE chain).
