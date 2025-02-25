#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical, rw_only_or_physical
from salt://lib/defs.sls import Perms, ReloadSystemdOnchanges
from salt://prometheus/config.sls import config


reloadsystemd = ReloadSystemdOnchanges(sls)
port = 7500

if fully_persistent_or_physical():
    p = Pkg.installed("tang").requisite
    m = Qubes.enable_dom0_managed_service(
        'tangd.socket',
        qubes_service_name="tangd",
        require=[p]
    ).requisite
    o = File.managed(
        f"/etc/systemd/system/tangd.socket.d/listen-{port}.conf",
        contents=f"""
[Socket]
ListenStream=
ListenStream={port}
""".strip(),
        makedirs=True,
        require=[m],
        watch_in=[reloadsystemd]
    ).requisite
    preqs = [o]
else:
    preqs = []

selinux = Selinux.port_policy_present(
    f"Tang on port {port}",
    sel_type="tangd_port_t",
    protocol="tcp",
    port=port,
    require=preqs,
).requisite

if rw_only_or_physical():
    q = Qubes.bind_dirs(
        "90-tang",
        directories=["/var/db/tang"],
        require=preqs,
        require_in=[reloadsystemd, selinux],
    ).requisite
