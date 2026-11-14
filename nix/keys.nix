# Public SSH keys allowed to log in to homelab machines.
#
# Used for both the normal sshd (as the admin user) and the initrd sshd used for
# remote disk unlocking (as root). Keys live in 1Password; copy the *public*
# halves here.
#
# The build fails on purpose while this list is empty (see modules/base.nix);
# otherwise you would be locked out of the machine.
{
  admins = [
    # 1Password: "homelab admin" (vault Homelab). docs/bootstrap.md#prepare-the-admin-keys
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILp/ebsWDFc35LNMutnREANZw4YCCDdBbvMhaWoMsp6k"
  ];
}
