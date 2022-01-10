#!objects

import os

from salt://lib/qubes.sls import rw_only_or_physical, fully_persistent_or_physical



if fully_persistent_or_physical():
    with Pkg.installed("certbot"):
        Qubes.enable_dom0_managed_service("certbot-renew", enable=False)
    deps = [Qubes("certbot-renew")]
else:
    deps = []

if rw_only_or_physical():
    ssl = pillar("matrix:ssl", {})
    renewal_email = pillar("matrix:ssl", {})["renewal_email"]
    certbot_webroot = "/etc/letsencrypt/webroot"
    delegated_hostname = ssl["delegated_hostname"]
    cert_dir = os.path.join("/etc/letsencrypt/live", delegated_hostname)
    cert = os.path.join(cert_dir, "fullchain.pem")
    key = os.path.join(cert_dir, "privkey.pem")

    with Qubes.bind_dirs(
        '90-matrix-certbot',
        directories=['/etc/letsencrypt'],
        require=deps,
    ):
        File.directory(
            certbot_webroot,
            require=[Qubes('90-matrix-certbot')],
        )

    if not (salt.file.file_exists(cert) and salt.file.file_exists(key)):
        include("matrix.nginx")
        Cmd.run(
            "generate certificate",
            name="certbot certonly -m %s --agree-tos --webroot -w %s -d %s" % (
                salt.text.quote(renewal_email),
                salt.text.quote(certbot_webroot),
                salt.text.quote(delegated_hostname),
            ),
            require=[
                File(certbot_webroot),
                Service("nginx before obtaining SSL certificate"),
            ] + deps,
            watch_in=[
                Service("nginx after obtaining SSL certificate"),
            ],
            require_in=[
                File("/etc/letsencrypt/renewal-hooks/post/nginx"),
                File("/etc/nginx/nginx.conf after obtaining SSL certificate"),
            ],
            creates=cert_dir,
        )
    else:
        Cmd.wait(
            "generate certificate",
            name="echo Certificates are already generated",
            require=deps,
        )
