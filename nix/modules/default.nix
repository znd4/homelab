# Everything a homelab NixOS host imports. Service modules do nothing until a
# host sets `homelab.services.<name>.enable = true`.
{
  imports = [
    ./base.nix
    ./remote-unlock.nix
    ./reverse-proxy.nix
    ./services/cups.nix
    ./services/dns.nix
  ];
}
