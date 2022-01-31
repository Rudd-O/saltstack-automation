#!objects

import os


from salt://lib/qubes.sls import rw_only_or_physical, fully_persistent_or_physical


if fully_persistent_or_physical():
    with Pkg.installed("matrix-synapse"):
        Qubes.enable_dom0_managed_service("synapse")
    Pkg.installed("python3-systemd")
    Pkg.installed("python3-psycopg2")
    Pkg.installed("python3-lxml") # Needed for URL previews.
    deps = [
        Pkg("python3-systemd"),
        Pkg("python3-psycopg2"),
        Pkg("python3-lxml"),
        Qubes("synapse"),
    ]
else:
    deps = []

if rw_only_or_physical():
    context = pillar("matrix:synapse", {})
    datadir = context.setdefault("datadir", "/var/lib/synapse")
    confdir = context.setdefault("confdir", "/etc/synapse")
    signing_key_path = context.setdefault(
        "signing_key_path",
        os.path.join(confdir, context["server_name"] + ".signing.key"),
    )
    Qubes.bind_dirs(
        '90-matrix-synapse',
        directories=[datadir, confdir, '/etc/sysconfig/synapse'],
        require=deps,
    )
    File.directory(
        confdir,
        mode="0750",
        user="root",
        group="synapse",
        require=[Qubes('90-matrix-synapse')]
    )
    Cmd.run(
        "/usr/bin/generate_signing_key.py -o " + salt.text.quote(signing_key_path),
        creates=signing_key_path,
        require=[Qubes('90-matrix-synapse'), File(confdir)],
        watch_in=[Service("synapse")],
    )
    File.managed(
        confdir + "/homeserver.yaml",
        source="salt://matrix/synapse/homeserver.yaml.j2",
        template="jinja",
        context=context,
        mode="640",
        user="root",
        group="synapse",
        require=[Qubes('90-matrix-synapse')],
        watch_in=[Service("synapse")],
    )
    Service.running(
        "synapse",
        enable=True,
    )
