#!objects

from salt://lib/qubes.sls import template, fully_persistent_or_physical


if fully_persistent_or_physical():
    with Pkg.installed("mariadb-server"):
        q = Qubes.enable_dom0_managed_service("mariadb").requisite
    dbclient = Pkg.installed("python3-mysqlclient").requisite
    deps = [q, dbclient]
else:
    deps = []

Test.nop("Database setup", require=deps)

if not template():
    site_settings = pillar("mariadb:site_settings")
    if site_settings:
        conf = [File.managed(
            '/etc/my.cnf.d/site_settings.cnf',
            contents="""
{% for key, group in site_settings.items() %}
[{{ key }}]
{% for setting, val in group.items() %}
{{ setting }}={{ val }}
{% endfor %}
{% endfor %}
""",
            template="jinja",
            context={
                "site_settings": site_settings,
            },
            require=deps,
        ).requisite]
    else:
        conf = [File.absent('/etc/my.cnf.d/site_settings.cnf').requisite]
    b = Qubes.bind_dirs(
        '90-mariadb',
        directories=['/var/lib/mysql'] + (
            ["/etc/my.cnf.d/site_settings.cnf"] if site_settings else []
        ),
        require=deps + (conf if site_settings else []),
        require_in=([] if site_settings else conf),
    ).requisite
    s = Service.running(
        "mariadb",
        enable=True,
        watch=[b] + conf,
    ).requisite
    Cmd.run(
        "Database secured",
        name="set -e -o pipefail ; (echo ; echo y ; echo n ; echo y ; echo y ; echo y ; echo y) | mariadb-secure-installation ; touch /var/lib/mysql/.secured",
        creates="/var/lib/mysql/.secured",
        require=[s],
        require_in=[Test("Database setup")],
    )
