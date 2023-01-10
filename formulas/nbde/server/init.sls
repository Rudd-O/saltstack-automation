#!objects

from salt://lib/qubes.sls import Qubify, dom0, fully_persistent_or_physical, rw_only_or_physical
from salt://lib/defs.sls import Perms
from salt://prometheus/config.sls import config


if fully_persistent_or_physical():
    p = Pkg.installed("tang").requisite
    m = Qubes.enable_dom0_managed_service(
        'tangd.socket',
        qubes_service_name="tangd",
        require=[p]
    ).requisite
    o = File.managed(
        "/etc/systemd/system/tangd.socket.d/listen-7500.conf",
        contents="""
[Socket]
ListenStream=
ListenStream=7500
""".strip(),
        makedirs=True,
        require=[m],
    ).requisite
    preqs = [o]
else:
    preqs = []

if rw_only_or_physical():
    q = Qubes.bind_dirs(
        "90-tang",
        directories=["/var/db/tang"],
        require=preqs,
    ).requisite
    Cmd.wait(
        "systemctl daemon-reload for tangd",
        name="systemctl --system daemon-reload",
        watch=preqs,
        require=[q],
    )
