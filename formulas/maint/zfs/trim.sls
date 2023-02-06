#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical
from salt://lib/defs.sls import Perms


if fully_persistent_or_physical() or dom0():
    Cmd.run(
        "Dispatch trim",
        name="""
set -e
changed=no
for pool in $(zpool list -o name -H) ; do
    echo -n "$pool: " >&2
    zpool trim "$pool" && echo trimming >&2 || /bin/true
done
""",
    )
else:
    Test.nop("Nothing to do for this machine type.")
