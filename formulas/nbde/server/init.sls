#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical, rw_only_or_physical
from salt://lib/defs.sls import Perms, ReloadSystemdOnchanges
from salt://prometheus/config.sls import config


reloadsystemd = ReloadSystemdOnchanges(sls)

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
        watch_in=[reloadsystemd]
    ).requisite
    preqs = [o]
else:
    preqs = []

if rw_only_or_physical():
    q = Qubes.bind_dirs(
        "90-tang",
        directories=["/var/db/tang"],
        require=preqs,
        require_in=[reloadsystemd],
    ).requisite
