#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical
from salt://lib/flatpak.sls import flatpak_updated
from salt://maint/config.sls import config


if fully_persistent_or_physical() or dom0():
    tpl = "set -x ; mkdir -p /var/cache/salt/zfs-dkms ; test -f /var/cache/salt/zfs-dkms/%(stage)s || { rpm -qa | grep zfs-dkms > /var/cache/salt/zfs-dkms/%(stage)s ; } ; echo ; echo changed=no ; exit 0"
    if grains("os") in ["Fedora", "Qubes", "Qubes OS"]:
        include("needs-restart")
    Cmd.run(
        "Check ZFS module before",
        name=tpl % {"stage": "before"},
        creates="/var/cache/salt/zfs-dkms/before",
    )
    updreq = Mypkg.uptodate(
        "update packages",
        require=[Cmd("Check ZFS module before")],
    ).requisite

    freq = flatpak_updated(require=updreq)

    if grains("os") in ["Fedora", "Qubes", "Qubes OS"]:
        rest = Maint.services_restarted(
            "Restart services",
            require=[updreq, Test("needs-restart deployed")],
            exclude_services_globs=config['update'].restart_exclude_services,
            exclude_paths=config['update'].restart_exclude_paths,
        ).requisite
        if __salt__["service.available"]("needs-restart-collector"):
            Cmd.run(
                "systemctl start --no-block needs-restart-collector",
                onchanges=[rest],
            )
    Cmd.run(
        "Check ZFS module after",
        name=tpl % {"stage": "after"},
        stateful=True,
        require=[updreq],
    )
    Cmd.run(
        "Compare ZFS versions",
        name="set -x ; cat /var/cache/salt/zfs-dkms/before /var/cache/salt/zfs-dkms/after >&2 ; cmp /var/cache/salt/zfs-dkms/before /var/cache/salt/zfs-dkms/after >&2 || { echo ; echo changed=yes ; }",
        stateful=True,
        require=[Cmd("Check ZFS module after")],
    )
    with Cmd.script(
        "salt://maint/update/refresh-zfs-dkms.sh",
        args="force",
        onchanges=[Cmd("Compare ZFS versions")],
        stateful=True,
    ):
        Cmd.run("rm -rf /var/cache/salt/zfs-dkms", stateful=True)
else:
    Test.nop("Nothing to do for this machine type.")
