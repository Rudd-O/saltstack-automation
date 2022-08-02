#!objects

from salt://lib/qubes.sls import template


if grains("os") == "Fedora":
    include(sls + ".needs-restart-collector")
include(sls + ".systemd-unit-state-collector")

if template()
    reqs = []
else:
    reqs=  [
        Cmd("systemctl --system start --no-block systemd-unit-state-collector"),
    ]
    if grains("os") == "Fedora":
        reqs += [
            Cmd("systemctl --system start --no-block needs-restart-collector"),
        ]

Test.nop("After collector setup", require=reqs)
