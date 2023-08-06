#!pyobjects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical


if fully_persistent_or_physical() or dom0():
    Cmd.script(
        "salt://maint/update/refresh-zfs-dkms.sh",
        args="check",
    )
else:
    Test.nop("Nothing to do for this machine type.")
