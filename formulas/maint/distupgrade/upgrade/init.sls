#!objects

from salt://maint/config.sls import config


preup = [Test.nop("Preupgrade").requisite]
postup = [Test.nop("Postupgrade").requisite]


if pillar("fake"):
    upg = Cmd.run(
        "Upgrade system",
        name="/bin/true",
        require=preup,
    ).requisite
else:
    slsp = "/".join(sls.split("."))
    upg = Cmd.script(
        "Upgrade system",
        name="salt://" + slsp + "/dnf-distro-sync.sh",
        stateful=True,
        require=preup,
    ).requisite

refresh = Cmd.script(
    "Refresh ZFS DKMS",
    name="salt://maint/update/refresh-zfs-dkms.sh",
    args="force",
    stateful=True,
    require_in=postup,
    require=[upg],
).requisite

if grains("os") == "Fedora" and 0:
    include("needs-restart")
    Maint.services_restarted(
        "Restart services",
        require=[refresh, Test("needs-restart deployed")],
        require_in=postup,
        exclude_services_globs=config['update'].restart_exclude_services,
        exclude_paths=config['update'].restart_exclude_paths,
    )
