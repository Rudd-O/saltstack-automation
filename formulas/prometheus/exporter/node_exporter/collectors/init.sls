#!objects

from salt://lib/qubes.sls import template


include(sls + ".needs-restart-collector")
include(sls + ".systemd-unit-state-collector")

reqs = [] if template() else [
    Cmd("systemctl --system start --no-block needs-restart-collector"),
    Cmd("systemctl --system start --no-block systemd-unit-state-collector"),
]
Test.nop("After collector setup", require=reqs)
