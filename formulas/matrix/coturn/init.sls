#!objects

import os


from salt://lib/qubes.sls import template, fully_persistent_or_physical
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path, allow_user


include("letsencrypt")


deps = []
restartwatch = []
restartrequire = []

if fully_persistent_or_physical():
    with Pkg.installed("coturn"):
        Qubes.enable_dom0_managed_service("coturn")
    deps.extend([
       Qubes("coturn"),
    ])

    Cmd.wait(
        "reload systemd",
        name="systemctl --system daemon-reload",
    )
    restartrequire.append(Cmd("reload systemd"))

    for typ in [".service", ".timer", ""]:
        if typ:
            f = "/etc/systemd/system/coturn-update-external-ip%s" % typ
        else:
            f = "/usr/bin/coturn-update-external-ip%s" % typ
        File.managed(
            f,
            source="salt://matrix/coturn/coturn-update-external-ip%s" % typ,
            mode="0644" if typ else "0755",
            user="root",
            group="root",
            watch_in=[Cmd("reload systemd")] if typ else [],
            require=deps,
        )
        deps.append(File(f))
        if typ == ".timer":
            Service.enabled(
                "coturn-update-external-ip%s" % typ,
                require=deps[-1],
            )
    File.managed(
        "/etc/systemd/system/coturn.service.d/restart.conf",
        source="salt://matrix/coturn/restart.conf",
        makedirs=True,
        mode="0644",
        watch_in=[Cmd("reload systemd")],
    )
    deps.append(File("/etc/systemd/system/coturn.service.d/restart.conf"))
    restartwatch.append(File("/etc/systemd/system/coturn.service.d/restart.conf"))

    dis = Qubes.disable_dom0_managed_service(
        "coturn-update-external-ip",
        qubes_service_name="coturn-update-external-ip",
        disable=False,
        watch_in=[Cmd("reload systemd")],
        require=[File("/etc/systemd/system/coturn-update-external-ip.service")],
    ).requisite
    dep = Qubes.enable_dom0_managed_service(
        "coturn-update-external-ip.timer",
        qubes_service_name="coturn-update-external-ip",
        watch_in=[Cmd("reload systemd")],
        require=[dis],
    ).requisite
    deps.append(dep)
else:
    pass

if not template():
    context = pillar("matrix:coturn", {})
    realm = context["realm"]
    cert = fullchain_path(realm)
    key = privkey_path(realm)
    context["cert"] = cert
    context["key"] = key
    Qubes.bind_dirs(
        '90-matrix-coturn',
        directories=['/etc/coturn', '/var/lib/coturn'],
    )
    File.directory(
        '/etc/coturn',
        mode="0750",
        user="root",
        group="coturn",
        require=[Qubes("90-matrix-coturn")] + deps,
    )
    if context.get("get_external_ip_command"):
        assert "external_ip" not in context, "Cannot specify both external_ip and get_external_ip_command in the pillar"
        extip = salt.cmd.run(context.get("get_external_ip_command"), raise_err=True, rstrip=True)
        if hasattr(extip, "items"):
            # Uh oh the command did not succeed.
            assert 0, "The get_external_ip_command failed to run: %s %s" % (extip, type(extip))
        if not extip:
            # Uh oh the command returned empty.
            assert 0, "The get_external_ip_command returned no data."
        context["external_ip"] = extip.splitlines()[0]
    File.managed(
        "/etc/coturn/turnserver.conf",
        source="salt://matrix/coturn/turnserver.conf.j2",
        template="jinja",
        context=context,
        mode="640",
        user="root",
        group="coturn",
        require=[File('/etc/coturn')],
        watch_in=[Service("coturn")],
    )
    pre, post = allow_user(realm, "coturn", require=deps)
    Service.running(
        "coturn",
        enable=True,
        watch=[
            pre,
            File("/etc/coturn/turnserver.conf"),
        ] + restartwatch,
        require=restartrequire + [post],
    )
    # Create renewal hook to restart coturn.
    File.managed(
        "/etc/letsencrypt/renewal-hooks/post/coturn",
        contents="""
#!/bin/bash -e
systemctl restart coturn.service
        """.strip(),
        mode="0755",
        require=[
            Service("coturn"),
        ],
        makedirs=True,
    )
