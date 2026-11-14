# VM test for homelab.remoteUnlock: unlock a LUKS root over SSH in the initrd.
#
#   nix build .#checks.x86_64-linux.remote-unlock-vm      (needs KVM)
#
# The server first boots without encryption. The test formats a LUKS disk,
# then installs the `boot-luks` specialisation with systemd-boot and reboots.
# The bootloader install copies the host key into the initrd
# (boot.initrd.secrets), the same way as on real hardware.
#
# The client is the DHCP server for the test LAN, because the initrd uses DHCP.
{ self }:
{ lib, pkgs, ... }:
let
  keys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
  passphrase = "supersecret";
  serverIp = "192.168.1.2";
  # qemu-common.nix: 52:54:00:12:<vlan>:<node index>. Nodes sort by name, so server is 2.
  serverMac = "52:54:00:12:01:02";
  # Test-only initrd host key. On a real host the key is a file on disk (see
  # docs/bootstrap.md). In the test it must exist when the disk image is built,
  # because the image build installs the bootloader for all specialisations.
  initrdHostKey = pkgs.runCommand "initrd-test-host-key" { } ''
    ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f $out
  '';
in
{
  name = "homelab-remote-unlock";

  nodes = {
    server =
      { ... }:
      {
        imports = [ self.nixosModules.default ];
        _module.args = {
          homelabHosts = { };
          flakeRev = "test-rev";
          flakeLastModified = 1;
        };

        virtualisation = {
          emptyDiskImages = [ 512 ];
          useBootLoader = true;
          useEFIBoot = true;
          # Booting from the encrypted disk needs the host store for init.
          mountHostNixStore = true;
        };
        boot.loader.systemd-boot.enable = true;
        environment.systemPackages = [ pkgs.cryptsetup ];

        homelab = {
          authorizedKeys = [ keys.snakeOilEd25519PublicKey ];
          lanAddress = serverIp;
          # Off in the first boot, which has no encrypted disk.
          remoteUnlock.enable = lib.mkDefault false;
        };
        networking.useNetworkd = lib.mkForce false;

        specialisation.boot-luks.configuration = {
          homelab.remoteUnlock = {
            enable = true;
            # The option takes a plain string (a path on the running system),
            # so drop the store context and keep the key in the closure.
            hostKey = builtins.unsafeDiscardStringContext "${initrdHostKey}";
            kernelModules = [ "virtio_net" ];
            interfaceMatch = "eth1";
          };
          boot.initrd.luks.devices = lib.mkVMOverride {
            cryptroot.device = "/dev/vdb";
          };
          virtualisation.rootDevice = "/dev/mapper/cryptroot";
          system.extraDependencies = [ initrdHostKey ];
        };
      };

    client =
      { ... }:
      {
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = false;
          settings = {
            port = 0; # DHCP only
            interface = "eth1";
            dhcp-range = [ "192.168.1.100,192.168.1.150" ];
            dhcp-host = [ "${serverMac},${serverIp}" ];
          };
        };
        networking.firewall.allowedUDPPorts = [ 67 ];
        environment.etc.sshKey = {
          source = keys.snakeOilEd25519PrivateKey;
          mode = "0600";
        };
      };
  };

  testScript =
    { nodes, ... }:
    let
      boot-luks = nodes.server.specialisation.boot-luks.configuration.system.build.toplevel;
    in
    ''
      ssh = "ssh -i /etc/sshKey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p 2222 root@${serverIp}"

      start_all()
      client.wait_for_unit("dnsmasq.service")

      with subtest("prepare the LUKS root"):
          server.wait_for_unit("multi-user.target")
          server.succeed("echo -n ${passphrase} | cryptsetup luksFormat -q --iter-time=1 /dev/vdb -")
          server.succeed("echo -n ${passphrase} | cryptsetup luksOpen -q /dev/vdb cryptroot")
          server.succeed("mkfs.ext4 -q /dev/mapper/cryptroot")
          server.succeed("cryptsetup luksClose cryptroot")
          server.succeed("${boot-luks}/bin/switch-to-configuration boot")
          # Make the boot-luks entry the default. loader.conf is the fallback,
          # and the EFI variable (bootctl set-default) wins if it is set.
          entry = server.succeed("basename /boot/loader/entries/*specialisation-boot-luks*.conf").strip()
          server.succeed(f"sed -i 's/^default .*/default {entry}/' /boot/loader/loader.conf")
          server.succeed(f"bootctl set-default {entry}")
          server.succeed("sync")
          server.crash()

      server.start()

      with subtest("the server waits in the initrd and serves SSH on 2222"):
          # Do not use wait_for_console_text here. The driver reads the console
          # backlog at one line per second, so it is too slow after a reboot.
          client.wait_until_succeeds("${pkgs.netcat}/bin/nc -z ${serverIp} 2222", timeout=120)

      with subtest("the forced command gives no shell"):
          # No terminal: the forced command must refuse and send no passphrase.
          # An agent left behind here would block the unlock subtest.
          out = client.execute(f"timeout 10 {ssh} 'id; echo SHELL-OK' </dev/null 2>&1")[1]
          assert "uid=" not in out and "SHELL-OK" not in out, out
          assert "use ssh -t" in out, out

      with subtest("port forwarding is refused"):
          out = client.execute(f"timeout 10 {ssh} -W localhost:2222 </dev/null 2>&1")[1]
          assert "prohibited" in out, out

      with subtest("the passphrase over SSH unlocks the disk and boot continues"):
          client.execute(f"(sleep 3; echo ${passphrase}) | timeout 60 {ssh} -tt 2>&1")
          server.wait_for_unit("multi-user.target", timeout=180)
          assert "/dev/mapper/cryptroot on / type ext4" in server.succeed("mount")
    '';
}
