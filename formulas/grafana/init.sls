#!pyobjects

from salt://lib/qubes.sls import Qubify, dom0, fully_persistent_or_physical, rw_only_or_physical
from salt://lib/defs.sls import Perms
from salt://grafana/config.sls import config


pkgs = ["grafana"]


if fully_persistent_or_physical() and not dom0():
    include('grafana.repo')
    with Pkg.latest(
        "grafana-packages",
        pkgs=pkgs,
        require=[Test('grafana repo deployed')],
    ):
        Qubify("grafana-server")
    p = [Pkg("grafana-packages")]
else:
    p = []


if rw_only_or_physical() and not dom0():
    Service.running("grafana-server", require=[Qubes('grafana bind')])
    var = File.directory("/var/lib/grafana", require=p, user="root", group="grafana", mode="0770").requisite
    plugins = File.directory("/var/lib/grafana/plugins", require=[var], user="root", group="grafana", mode="0770").requisite
    with Service("grafana-server", "watch_in"):
        config = File.managed(
            '/etc/grafana/grafana.ini',
            source="salt://grafana/grafana.ini.j2",
            template='jinja',
            context={"grafana": config},
            require=p,
            user="root",
            group="grafana",
        ).requisite
        Cmd.run(
            "Install grafana plugins",
            name="""
    set -e
    grafana-cli plugins ls | grep camptocamp-prometheus-alertmanager-datasource >&2 || {
        grafana-cli plugins install camptocamp-prometheus-alertmanager-datasource >&2
        echo
        echo changed=yes
    }
    """,
            stateful=True,
            require=[config, Qubes("grafana bind")] + p,
        )
    Qubes.bind_dirs(
        'grafana bind',
        name="grafana",
        directories=['/var/lib/grafana', '/etc/grafana', '/etc/sysconfig/grafana', '/etc/sysconfig/grafana-server'],
        require=p + [plugins, config],
    )
