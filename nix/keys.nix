# Public SSH keys allowed to log in to homelab machines.
#
# Used for both the normal sshd (as the admin user) and the initrd sshd used for
# remote disk unlocking (as root). Keys live in 1Password; copy the *public*
# halves here.
#
# TODO(bootstrap): add at least one key before building an installer or deploying a host.
#   Runbook: docs/bootstrap.md#prepare-the-admin-keys (the SSH key steps).
# The build fails on purpose while this list is empty (see modules/base.nix);
# otherwise you would be locked out of the machine.
{
  admins = [
    # "ssh-ed25519 AAAA... znd4@1password"
  ];
}
