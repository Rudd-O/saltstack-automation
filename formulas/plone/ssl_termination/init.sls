#!objects

import os


from salt://lib/qubes.sls import template, physical
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path

include("nginx")
include("letsencrypt")


if not template():
    context = pillar(sls.replace(".", ":"), {})
    server_name = context["server_name"]
    cert = fullchain_path(server_name)
    key = privkey_path(server_name)
    backend = context.get("backend", "127.0.0.1:6081")

    if physical():
        Selinux.boolean(
            "httpd_can_network_relay",
            value=True,
            require_in=[Service("nginx")],
        )

    File.managed(
        "/etc/nginx/conf.d/vhosts/%s.conf" % server_name,
        name="/etc/nginx/conf.d/vhosts/%s.conf" % server_name,
        source="salt://nginx/vhost.conf.j2",
        template="jinja",
        makedirs=True,
        context={
            "ports": [443],
            "server_name": server_name,
            "max_upload_size": "1000M",
            "ssl_certificate": cert,
            "ssl_certificate_key": key,
            "server_config": """
                location / {
                    proxy_set_header X-Forwarded-For $remote_addr;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header Host $host;
                    proxy_pass http://%(backend)s;
                    # WebSockets.
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection $connection_upgrade;
                }
            """ % locals(),
        },
        require=[Qubes("90-matrix-nginx"), Test("all certificates generated")],
        watch_in=[Service("nginx")],
    )
