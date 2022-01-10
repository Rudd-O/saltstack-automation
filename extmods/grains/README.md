# Dealing with bugs in Salt SSH

Due to a bug in SaltStack, every time I modify a grain, I must wipe
the `/var/tmp/.root*salt*` directories in the SSH minions.  Otherwise
grains remain there and out of date or, worse, they disappear silently.

The option `ssh_wipe` in the `Saltfile` can be used to wipe the Salt
SSH cache directory in the SSH minions.  Turn it on, then run a
`test.ping` across the machines of the fleet that need to be wiped.

This bug has been elided by simply setting thin dir to /tmp/.salt-thin
in the master Salt config.

When you make changes to extmods, you must run salt-ssh with `-t`
in order to get the thin tarball regenerated.  You may also have to
`rm -rf /tmp/.salt-thin` in the machine.
