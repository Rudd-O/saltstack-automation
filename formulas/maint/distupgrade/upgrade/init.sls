#!objects

from salt://maint/config.sls import config


preup = [Test.nop("Preupgrade").requisite]
postup = [Test.nop("Postupgrade").requisite]

tpl = "set -x ; mkdir -p /var/cache/salt/zfs-dkms ; test -f /var/cache/salt/zfs-dkms/%(stage)s || { rpm -qa | grep zfs-dkms > /var/cache/salt/zfs-dkms/%(stage)s ; } ; echo ; echo changed=no ; exit 0"

if pillar("fake"):
    upg = Cmd.run(
        "Upgrade system",
        name="/bin/true",
        require=preup,
    ).requisite
    refresh = Cmd.script(
        "Refresh ZFS DKMS",
        name="/bin/true",
        require_in=postup,
        require=[upg],
    ).requisite
else:
    slsp = "/".join(sls.split("."))
    checkbefore = Cmd.run(
        "Check ZFS module before",
        name=tpl % {"stage": "before"},
        creates="/var/cache/salt/zfs-dkms/before",
        require=preup
    ).requisite
    upg = Cmd.script(
        "Upgrade system",
        name="salt://" + slsp + "/dnf-distro-sync.sh",
        stateful=True,
        require=[checkbefore],
    ).requisite
    checkafter = Cmd.run(
        "Check ZFS module after",
        name=tpl % {"stage": "after"},
        stateful=True,
        require=[upg],
    ).requisite
    compare = Cmd.run(
        "Compare ZFS versions",
        name="set -x ; cat /var/cache/salt/zfs-dkms/before /var/cache/salt/zfs-dkms/after >&2 ; cmp /var/cache/salt/zfs-dkms/before /var/cache/salt/zfs-dkms/after >&2 || { echo ; echo changed=yes ; }",
        stateful=True,
        require=[checkafter],
    ).requisite
    refresh = Cmd.script(
        "Refresh ZFS DKMS",
        name="salt://maint/update/refresh-zfs-dkms.sh",
        args="force",
        stateful=True,
        onchanges=[compare],
    ).requisite
    Cmd.run("rm -rf /var/cache/salt/zfs-dkms", stateful=True, require=[refresh], require_in=postup)

if grains("os") == "Fedora" and 0:
    include("needs-restart")
    Maint.services_restarted(
        "Restart services",
        require=[refresh, Test("needs-restart deployed")],
        require_in=postup,
        exclude_services_globs=config['update'].restart_exclude_services,
        exclude_paths=config['update'].restart_exclude_paths,
    )
