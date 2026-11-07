# Single disk: ESP + LUKS2 -> btrfs subvolumes. Unlocked at boot by passphrase,
# typed on the console or over SSH (see modules/remote-unlock.nix).
#
# The passphrase is read from /tmp/secret.key only while formatting.
# nixos-anywhere uploads it with `--disk-encryption-keys`; see docs/bootstrap.md.
{
  disko.devices.disk.main = {
    type = "disk";
    # TODO(bootstrap): replace with the stable /dev/disk/by-id/... path from the installer
    # (`ls -l /dev/disk/by-id`).
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
