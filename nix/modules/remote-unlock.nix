# Remote LUKS unlock: an SSH server in the (systemd) initrd so an encrypted
# machine can be unlocked headlessly after a reboot.
#
#   ssh -p 2222 root@<host>      # prompts for the LUKS passphrase, then boot continues
#
# Enabled by default on every host. NIC drivers for the initrd come from the
# host's nixos-facter report (hardware.facter.reportPath); hosts without one
# must set `homelab.remoteUnlock.kernelModules`.
#
# Threat model: the initrd (including its SSH host key) lives on the
# *unencrypted* ESP. Anyone with physical access can read that key and
# impersonate the unlock prompt. So:
#   - the key is dedicated to the initrd and is never the real host key;
#   - it listens on its own port, so known_hosts never confuses the two keys;
#   - the forced command only answers password prompts; no shell is exposed;
#   - the forced command needs a terminal (`ssh -t`), see forcedCommand.
#
# Every LUKS device gets `tries=0` (ask again until the passphrase is
# correct). Each SSH session that closes counts as one attempt, also an empty
# one. With the systemd default (3 tries), dropped sessions put the machine in
# emergency mode, which is on the local console only. Only a holder of an
# admin SSH key can make an attempt, so unlimited tries do not help an attacker.
# See https://wiki.nixos.org/wiki/Remote_disk_unlocking
{ config, lib, ... }:
let
  cfg = config.homelab.remoteUnlock;
  # The agent runs only on a terminal. Without one, the agent reads EOF, sends
  # an empty passphrase, and repeats this for each new prompt. It also does not
  # stop when the client disconnects, so it blocks all later attempts. On a
  # terminal, a disconnect sends SIGHUP and the agent stops.
  forcedCommand = "if test -t 0; then exec systemd-tty-ask-password-agent --watch; else echo use ssh -t >&2; exit 1; fi";
in
{
  options.homelab.remoteUnlock = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run sshd in the initrd so LUKS can be unlocked remotely.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 2222;
    };
    hostKey = lib.mkOption {
      # A string, not a path: a path would copy the private key into the
      # world-readable nix store.
      type = lib.types.str;
      default = "/etc/secrets/initrd/ssh_host_ed25519_key";
      description = ''
        Private initrd host key on the *running* system. It is copied into the
        initrd when the bootloader is installed. Generate it per host before
        install; see docs/bootstrap.md.
      '';
    };
    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "r8169"
        "igc"
      ];
      description = ''
        Extra NIC driver modules for the initrd. Not needed when the host has a
        facter report, which detects them. Otherwise, on the target:
        `lspci -k | grep -A3 -i ethernet` ("Kernel driver in use").
      '';
    };
    interfaceMatch = lib.mkOption {
      type = lib.types.str;
      default = "en*";
      description = "systemd.network `Name=` match for the interface that gets DHCP in the initrd.";
    };
  };

  # Extend the submodule of every LUKS device (also devices that disko adds).
  options.boot.initrd.luks.devices = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.crypttabExtraOpts = lib.mkIf cfg.enable [ "tries=0" ];
      }
    );
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.facter.enable || cfg.kernelModules != [ ];
        message = "homelab.remoteUnlock: no facter report and no kernelModules, so the initrd would have no NIC driver.";
      }
    ];

    boot.initrd = {
      systemd.enable = true;
      availableKernelModules = cfg.kernelModules;

      systemd.network = {
        enable = true;
        networks."10-unlock" = {
          matchConfig.Name = cfg.interfaceMatch;
          networkConfig.DHCP = "yes";
          linkConfig.RequiredForOnline = "routable";
        };
      };

      network.enable = true;
      network.ssh = {
        enable = true;
        inherit (cfg) port;
        hostKeys = [ cfg.hostKey ];
        authorizedKeys = map (
          k: ''command="${forcedCommand}",no-port-forwarding,no-agent-forwarding,no-X11-forwarding '' + k
        ) config.homelab.authorizedKeys;
      };
    };
  };
}
