#!objects

import os


from salt://lib/qubes.sls import rw_only_or_physical, fully_persistent_or_physical


if fully_persistent_or_physical():
    with Pkg.installed("nginx"):
        Qubes.enable_dom0_managed_service("nginx")
    deps = [Qubes("nginx")]
else:
    deps = []

if rw_only_or_physical():
    synapse = pillar("matrix:synapse", {})
    ssl = pillar("matrix:ssl", {})
    renewal_email = pillar("matrix:ssl", {})["renewal_email"]
    certbot_webroot = "/etc/letsencrypt/webroot"
    delegated_hostname = ssl["delegated_hostname"]
    cert_dir = os.path.join("/etc/letsencrypt/live", delegated_hostname)
    cert = os.path.join(cert_dir, "fullchain.pem")
    key = os.path.join(cert_dir, "privkey.pem")

    Qubes.bind_dirs(
        '90-matrix-nginx',
        directories=['/etc/nginx'],
        require=deps,
    )

    if not (salt.file.file_exists(cert) and salt.file.file_exists(key)):
        File.managed(
            "/etc/nginx/nginx.conf before obtaining SSL certificate",
            name="/etc/nginx/nginx.conf",
            source="salt://matrix/nginx/nginx.conf.j2",
            template="jinja",
            context={
                "delegated_hostname": delegated_hostname,
                "max_upload_size": synapse.get("max_upload_size", "50M"),
                "certbot_webroot": certbot_webroot,
            },
            require=[Qubes("90-matrix-nginx")],
        )
        Service.running(
            "nginx before obtaining SSL certificate",
            name="nginx",
            enable=True,
            watch=[
                File("/etc/nginx/nginx.conf before obtaining SSL certificate"),
            ],
            require_in=[
                File("/etc/nginx/nginx.conf after obtaining SSL certificate"),
            ],
            require=deps,
        )

    File.managed(
        "/etc/nginx/nginx.conf after obtaining SSL certificate",
        name="/etc/nginx/nginx.conf",
        source="salt://matrix/nginx/nginx.conf.j2",
        template="jinja",
        context={
            "delegated_hostname": delegated_hostname,
            "max_upload_size": synapse.get("max_upload_size", "50M"),
            "certbot_webroot": certbot_webroot,
            "ssl_certificate": cert,
            "ssl_certificate_key": key,
        },
        require=[Qubes("90-matrix-nginx")],
    )
    Service.running(
        "nginx after obtaining SSL certificate",
        name="nginx",
        enable=True,
        watch=[
            File("/etc/nginx/nginx.conf after obtaining SSL certificate"),
        ],
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
    )
