#!objects

from salt://lib/qubes.sls import updateable


if grains("os") in ("Fedora", "Qubes", "Qubes OS"):
    include(sls + ".needs-restart-collector")
include(sls + ".systemd-unit-state-collector")

reqs=  [
    Cmd("systemctl --system restart --no-block systemd-unit-state-collector"),
]
if grains("os") in ("Fedora", "Qubes", "Qubes OS"):
    reqs += [
        Cmd("systemctl --system restart --no-block needs-restart-collector"),
    ]
