#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical
from salt://lib/flatpak.sls import flatpak_updated
from salt://maint/config.sls import config


cdi = __salt__["file.file_exists"]("/etc/cdi/nvidia.yaml")


if fully_persistent_or_physical() or dom0():
    tpl = "set -x ; mkdir -p /var/cache/salt/%(what)s ; test -f /var/cache/salt/%(what)s/%(stage)s || { rpm -qa | grep %(what)s > /var/cache/salt/%(what)s/%(stage)s ; } ; echo ; echo changed=no ; exit 0"

    Cmd.run(
        "Check ZFS module before",
        name=tpl % {"stage": "before", "what": "zfs-dkms"},
        creates="/var/cache/salt/zfs-dkms/before",
        stateful=True,
    )

    cdidepbefore = [Cmd.run(
        "Check NVIDIA drivers before",
        name=tpl % {"stage": "before", "what": "nvidia"},
        creates="/var/cache/salt/nvidia/before",
        stateful=True,
    ).requisite] if cdi else []

    updreq = Mypkg.uptodate(
        "update packages",
        require=[Cmd("Check ZFS module before")] + cdidepbefore,
    ).requisite

    freq = flatpak_updated(require=updreq)
 
    if grains("os") in ["Fedora", "Qubes", "Qubes OS"]:
        include("needs-restart")
        rest = Maint.services_restarted(
            "Restart services",
            require=[updreq, Test("needs-restart deployed")] + ([Cmd("NVIDIA CDI")] if cdi else []),
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
        name=tpl % {"stage": "after", "what": "zfs-dkms"},
        stateful=True,
        require=[updreq],
    )
    Cmd.run(
        "Compare ZFS versions",
        name="set -x ; cat /var/cache/salt/zfs-dkms/before /var/cache/salt/zfs-dkms/after >&2 ; cmp /var/cache/salt/zfs-dkms/before /var/cache/salt/zfs-dkms/after >&2 || { echo ; echo changed=yes ; }",
        stateful=True,
        require=[Cmd("Check ZFS module after")],
    )
    Cmd.script(
        "Refresh ZFS DKMS",
        name="salt://maint/update/refresh-zfs-dkms.sh",
        args="force",
        onchanges=[Cmd("Compare ZFS versions")],
        stateful=True,
    )
    Cmd.run("rm -rf /var/cache/salt/zfs-dkms", stateful=True, require=[Cmd("Refresh ZFS DKMS")])
    
    if cdi:
        cdidepafter = [Cmd.run(
            "Check NVIDIA drivers after",
            name=tpl % {"stage": "after", "what": "nvidia"},
            stateful=True,
            require=[updreq],
        ).requisite] if cdi else []
        Cmd.run(
            "Compare NVIDIA drivers",
            name="set -x ; cat /var/cache/salt/nvidia/before /var/cache/salt/nvidia/after >&2 ; cmp /var/cache/salt/nvidia/before /var/cache/salt/nvidia/after >&2 || { echo ; echo changed=yes ; }",
            stateful=True,
            require=cdidepafter,
            require_in=[File("Erase /etc/cdi/nvidia.yaml")],
        )
        File.absent(
            "Erase /etc/cdi/nvidia.yaml",
            name="/etc/cdi/nvidia.yaml",
            onchanges=[Cmd("Compare NVIDIA drivers")],
            require_in=[Cmd("NVIDIA CDI")],
        )
        include("ai.cdi")
        Cmd.run("rm -rf /var/cache/salt/nvidia", stateful=True, require=[Cmd("NVIDIA CDI")])

else:
    Test.nop("Nothing to do for this machine type.")
