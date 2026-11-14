# Single disk: ESP + LUKS2 -> btrfs subvolumes. Unlocked at boot by passphrase,
# typed on the console or over SSH (see modules/remote-unlock.nix).
#
# The passphrase is read from /tmp/secret.key only while formatting.
# nixos-anywhere uploads it with `--disk-encryption-keys`; see docs/bootstrap.md.
{
  disko.devices.disk.main = {
    type = "disk";
    # TODO(bootstrap): the /dev/disk/by-id/... path of the install disk.
    #   It is not arbitrary: the kernel builds it from the disk model and serial number,
    #   for example nvme-Samsung_SSD_980_1TB_S64DNX0R123456. You read it on the machine,
    #   so boot the installer first (section 3), then copy it here (section 4, step 3).
    #   Why not /dev/nvme0n1: that name depends on probe order. With a second disk it can
    #   point at the wrong one, and disko erases the disk that it points at.
    #   With exactly one disk in the machine, /dev/nvme0n1 also works.
    #   Runbook: docs/bootstrap.md, section 4 "Get the hardware facts".
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "crypted";
            passwordFile = "/tmp/secret.key";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes =
                let
                  opts = [
                    "compress=zstd"
                    "noatime"
                  ];
                in
                {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = opts;
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = opts;
                  };
                  "/var" = {
                    mountpoint = "/var";
                    mountOptions = opts;
                  };
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = opts;
                  };
                };
            };
          };
        };
      };
    };
  };
}
