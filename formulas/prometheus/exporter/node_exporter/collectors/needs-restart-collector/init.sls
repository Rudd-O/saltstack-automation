#!objects

from salt://prometheus/exporter/node_exporter/collectors/lib.sls import collector
from salt://lib/qubes.sls import template


include("needs-restart")

if not template():
    Test.nop(
        extend("needs-restart deployed"),
        require_in=[Cmd("systemctl --system start --no-block needs-restart-collector")],
    )

collector(sls.split(".")[-1], ".j2")
