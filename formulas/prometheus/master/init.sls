#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical, rw_only_or_physical
from salt://lib/defs.sls import Perms
from salt://prometheus/config.sls import config


pkgs = ["prometheus2", "alertmanager"]
svcs = pkgs[:]
svcs.remove('prometheus2')
svcs.append('prometheus')


if fully_persistent_or_physical() and not dom0():
    include('build.repo.client')
    with Pkg.latest(
        "prometheus-packages",
        pkgs=pkgs,
        require=[Test('repo deployed')],
    ):
        for svc in svcs:
            Qubes.enable_dom0_managed_service(
                "Qubes dom0 service " + svc,
                name=svc,
            )
    File.directory(
        '/etc/amtool',
        **Perms.dir
    )


if rw_only_or_physical() and not dom0():
    perms = Perms("prometheus")

    Qubes.bind_dirs(
        'prometheus',
        directories=['/var/lib/prometheus'],
    )

    Qubes.bind_dirs(
        'prometheus-config',
        directories=[
            '/etc/default/prometheus',
            '/etc/default/alertmanager',
            '/etc/prometheus/prometheus.yml',
            '/etc/prometheus/alerting.rules',
            '/etc/prometheus/recording.rules',
            '/etc/prometheus/alertmanager.yml',
            '/etc/amtool/config.yml',
        ],
    )

    for d in ["/var/lib/prometheus/data", "/var/lib/prometheus/alertmanager"]:
        File.directory(
            d,
            require=[Pkg("prometheus-packages")] if grains('qubes:persistence') == "" else [],
            require_in=[Qubes("prometheus")],
            **perms.owner_dir
        )
    for svc in svcs:
        binds = [Qubes("prometheus"), Qubes("prometheus-config")]
        Service.running(svc, require=binds)
        if svc in ["prometheus", "alertmanager"]:
            # These services support reloading.
            Service.running(svc + " (reloaded)", name=svc, reload=True, require=binds)
    with Service("prometheus", "watch_in"):
        File.managed(
            '/etc/default/prometheus',
            contents="PROMETHEUS_OPTS='" + " ".join([
                "--web.external-url={{ url }}",
                "--config.file=/etc/prometheus/prometheus.yml",
                "--storage.tsdb.path=/var/lib/prometheus/data",
                "--storage.tsdb.retention.size={{ retention }}",
            ]) + "'",
            template='jinja',
            context=config.master,
            require=[Pkg("prometheus-packages")] if grains('qubes:persistence') == "" else [],
            require_in=[Qubes("prometheus-config")],
        )
    with Service("prometheus (reloaded)", "watch_in"):
        for f in ['alerting.rules', 'prometheus.yml', 'recording.rules']:
            File.managed(
                '/etc/prometheus/%s' % f,
                source='salt://prometheus/master/%s.j2' % f,
                template='jinja',
                context=config.master,
                require=[Pkg("prometheus-packages")] if grains('qubes:persistence') == "" else [],
                require_in=[Qubes("prometheus-config")],
            )
    with Service("alertmanager", "watch_in"):
        File.managed(
            '/etc/default/alertmanager',
            contents="ALERTMANAGER_OPTS='--web.external-url={{ url }} --storage.path=/var/lib/prometheus/data'",
            template='jinja',
            context=config.alertmanager,
            require=[Pkg("prometheus-packages")] if grains('qubes:persistence') == "" else [],
            require_in=[Qubes("prometheus-config")],
        )
    with Service("alertmanager (reloaded)", "watch_in"):
        for f in ['alertmanager.yml']:
            File.managed(
                '/etc/prometheus/%s' % f,
                source='salt://prometheus/master/%s.j2' % f,
                template='jinja',
                context=config.alertmanager,
                require=[Pkg("prometheus-packages")] if grains('qubes:persistence') == "" else [],
                require_in=[Qubes("prometheus-config")],
            )
    File.managed(
        '/etc/amtool/config.yml',
        contents="alertmanager.url: 'http://localhost:9093/'",
        template='jinja',
        require_in=[Qubes("prometheus-config")],
    )
