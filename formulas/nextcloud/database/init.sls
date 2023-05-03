#!objects


from salt://lib/qubes.sls import template, fully_persistent_or_physical


if fully_persistent_or_physical():
    with Pkg.installed("mariadb-server"):
        q = Qubes.enable_dom0_managed_service("mariadb").requisite
    dbclient = Pkg.installed("python3-mysqlclient").requisite
    deps = [q, dbclient]
else:
    deps = []

if not template():
    include(".dataenv")
    b = Qubes.bind_dirs(
        '90-mariadb',
        directories=['/var/lib/mysql'],
        require=deps,
    ).requisite
    s = Service.running(
        "mariadb",
        enable=True,
        watch=[b],
    ).requisite
    Cmd.run(
        "set -e -o pipefail ; (echo ; echo y ; echo n ; echo y ; echo y ; echo y ; echo y) | mariadb-secure-installation ; touch /var/lib/mysql/.secured",
        creates="/var/lib/mysql/.secured",
        require=[s],
        require_in=Test("Nextcloud database environment not yet defined")
    )
