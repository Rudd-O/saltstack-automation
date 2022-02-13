#!objects

from salt://lib/qubes.sls import rw_only_or_physical, fully_persistent_or_physical
from salt://lib/letsencrypt.sls import certbot_webroot, certbot_live, certificate_dir, fullchain_path, privkey_path


include("nginx")


if fully_persistent_or_physical():
    with Pkg.installed("certbot"):
        Qubes.enable_dom0_managed_service("certbot-renew", enable=False)
    deps = [Qubes("certbot-renew")]
else:
    deps = []

if rw_only_or_physical():
    context = pillar("letsencrypt", {})
    default_renewal_email = context.get("renewal_email")
    hosts = context["hosts"]

    with Qubes.bind_dirs(
        '90-matrix-certbot',
        directories=['/etc/letsencrypt'],
        require=deps,
    ):
        File.directory(
            certbot_webroot,
            require=[Qubes('90-matrix-certbot')],
            require_in=[Service("nginx running in HTTP-only mode")],
        )

    for host, data in hosts.items():
        renewal_email = data.get("renewal_email", default_renewal_email)
        if not renewal_email:
            raise KeyError("a renewal_email is needed by default in letsencrypt pillar or for the host")
        cert = fullchain_path(host)
        key = privkey_path(host)
    
        if not (salt.file.file_exists(cert) and salt.file.file_exists(key)):
            C = Cmd.run
            cmd = "certbot certonly -m %s --agree-tos --webroot -w %s -d %s" % (
                salt.text.quote(renewal_email),
                salt.text.quote(certbot_webroot),
                salt.text.quote(host),
            )
        else:
            C = Cmd.wait
            cmd = "echo Certificates are already generated"
        C(
            "generate certificate for %s" % host,
            name=cmd,
            require=[Service("nginx running in HTTP-only mode")] + deps,
            watch_in=[Service("nginx")],
            require_in=[Test("all certificates generated")],
            creates=cert,
        )

    Test.nop(
        "all certificates generated",
        require_in=[Service("nginx")],
    )

    # Create renewal hook to reload NginX.
    File.managed(
        "/etc/letsencrypt/renewal-hooks/post/nginx",
        contents="""
#!/bin/bash -e
systemctl reload nginx.service
        """.strip(),
        mode="0755",
        makedirs=True,
        require=[Service("nginx")],
    )
