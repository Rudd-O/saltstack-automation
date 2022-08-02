#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical
from salt://maint/config.sls import config


if __salt__["file.file_exists"]("/.distupgrade"):
    curr = int(__salt__["file.read"]("/.distupgrade"))
else:
    curr = int(grains("osmajorrelease"))
next_ = curr + 1

include(".".join(sls.split(".")[:-1]) + ".prepare")


preup = Test.nop("Preupgrade").requisite
postup = Test.nop("Postupgrade").requisite


if dom0():
    assert 0, "not supported"
elif fully_persistent_or_physical():
    include("needs-restart")
    File.managed(
        "Create distupgrade marker",
        name="/.distupgrade",
        contents=str(curr),
        require=[preup],
    )
    if pillar("fake"):
        Cmd.run(
            "Upgrade system from %s %s to %s" % (grains("osfullname"), curr, next_),
            name="/bin/true",
            require=[File("Create distupgrade marker")],
            require_in=[Cmd("Refresh ZFS DKMS")],
        )
    else:
        slsp = "/".join(sls.split("."))
        Cmd.script(
            "Upgrade system from %s %s to %s" % (grains("osfullname"), curr, next_),
            name="salt://" + slsp + "/dnf-distro-sync.sh",
            args="%s" % (next_,),
            stateful=True,
            require=[File("Create distupgrade marker")],
            require_in=[Cmd("Refresh ZFS DKMS")],
        )
    Cmd.script(
        "Refresh ZFS DKMS",
        name="salt://maint/update/refresh-zfs-dkms.sh",
        args="force",
        stateful=True,
    )
    Maint.services_restarted(
        "Restart services",
        require=[Cmd("Refresh ZFS DKMS"), Test("needs-restart deployed")],
        require_in=[postup],
        exclude_services_globs=config['update'].restart_exclude_services,
        exclude_paths=config['update'].restart_exclude_paths,
    )
else:
    Test.nop(
        "This VM is not to be upgraded.",
        require=[preup],
        require_in=[postup],
    )
