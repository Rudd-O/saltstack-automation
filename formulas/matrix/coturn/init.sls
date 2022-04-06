#!objects

import os


from salt://lib/qubes.sls import template, fully_persistent_or_physical
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path, certificate_dir


include("letsencrypt")


deps = []
if fully_persistent_or_physical():
    with Pkg.installed("coturn"):
        Qubes.enable_dom0_managed_service("coturn")
    Cmd.wait(
        "reload systemd",
        name="systemctl --system daemon-reload",
    )
    deps.extend([
       Qubes("coturn"),
       Qubes("coturn-update-external-ip"),
    ])
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
    Qubes.enable_dom0_managed_service(
        "coturn-update-external-ip",
        watch_in=[Cmd("reload systemd")],
        require=[File("/etc/systemd/system/coturn-update-external-ip.service")],
    )
else:
    pass

if not template():
    context = pillar("matrix:coturn", {})
    realm = context["realm"]
    cert_dir = certificate_dir(realm)
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
            assert 0, type
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
    Cmd.run(
        "Set coturn ACL for certificates",
        name="setfacl -R -m u:coturn:rX %s %s %s && setfacl -m u:coturn:rX %s %s" % (
            salt.text.quote(cert),
            salt.text.quote(key),
            salt.text.quote(cert_dir),
            salt.text.quote("/etc/letsencrypt/live"),
            salt.text.quote("/etc/letsencrypt/archive"),
        ),
        unless=" && ".join([
            "getfacl %s | grep -q user:coturn:" % salt.text.quote(cert),
            "getfacl %s | grep -q user:coturn:" % salt.text.quote(key),
            "getfacl %s | grep -q user:coturn:" % salt.text.quote(cert_dir),
            "getfacl /etc/letsencrypt/live | grep -q user:coturn:",
            "getfacl /etc/letsencrypt/archive | grep -q user:coturn:",
        ]),
        require=[Test("all certificates generated")],
    )
    Service.running(
        "coturn",
        enable=True,
        watch=[
            Cmd("Set coturn ACL for certificates"),
            File("/etc/coturn/turnserver.conf"),
        ],
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
