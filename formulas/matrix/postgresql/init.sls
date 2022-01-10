#!objects


from salt://lib/qubes.sls import rw_only_or_physical, fully_persistent_or_physical


if fully_persistent_or_physical():
    with Pkg.installed("postgresql-server"):
        Qubes.enable_dom0_managed_service("postgresql")
    deps = [Qubes("postgresql")]
else:
    deps = []

if rw_only_or_physical():
    context = pillar("matrix:postgresql", {})
    Qubes.bind_dirs(
        '90-postgresql',
        directories=['/var/lib/pgsql'],
        require=deps,
    )
    Cmd.run(
        "postgresql-setup --initdb",
        creates="/var/lib/pgsql/data/postgresql.conf",
        require=[Qubes('90-postgresql')],
        watch_in=[Service("postgresql")],
    )
    for n, src in enumerate(["127.0.0.1/32", "::1/128"]):
        File.replace(
            "%s scram auth" % n,
            name="/var/lib/pgsql/data/pg_hba.conf",
            pattern="host\\s+%s\\s+%s\\s+%s\\s+.+" % (context["name"], context["user"], src),
            repl="host    %s         %s         %s            scram-sha-256" % (context["name"], context["user"], src),
            prepend_if_not_found=True,
            require=[Cmd("postgresql-setup --initdb")],
            watch_in=[Service("postgresql")],
        )
    Service.running(
        "postgresql-reloaded",
        name="postgresql",
        reload=True,
        require_in=[Service("postgresql")],
    )
    Service.running(
        "postgresql",
        enable=True,
        require_in=[Test("Synapse database environment not yet defined")],
    )
    include(".dataenv")
