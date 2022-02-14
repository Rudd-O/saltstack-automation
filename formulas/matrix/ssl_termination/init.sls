#!objects

import os


from salt://lib/qubes.sls import rw_only_or_physical, physical
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path

include("nginx")
include("letsencrypt")


if rw_only_or_physical():
    synapse = pillar("matrix:synapse", {})
    delegated_hostname = synapse["delegated_hostname"]
    cert = fullchain_path(delegated_hostname)
    key = privkey_path(delegated_hostname)

    if physical():
        Selinux.boolean(
            "httpd_can_network_relay",
            value=True,
            require_in=[Service("nginx")],
        )

    File.managed(
        "/etc/nginx/conf.d/vhosts/%s.conf" % delegated_hostname,
        name="/etc/nginx/conf.d/vhosts/%s.conf" % delegated_hostname,
        source="salt://nginx/vhost.conf.j2",
        template="jinja",
        makedirs=True,
        context={
            "ports": [443, 8448],
            "server_name": delegated_hostname,
            "max_upload_size": synapse.get("max_upload_size", "50M"),
            "ssl_certificate": cert,
            "ssl_certificate_key": key,
            "server_config": """
                location ~ ^(/_matrix|/_synapse/(client|admin)) {
                    # note: do not add a path (even a single /) after the port in `proxy_pass`,
                    # otherwise nginx will canonicalise the URI and cause signature verification
                    # errors.
                    # DO NOT USE LOCALHOST, always use an IP address.
                    proxy_pass http://%(backend)s;
                    proxy_set_header X-Forwarded-For $remote_addr;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header Host $host;
                    # WebSockets.
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection $connection_upgrade;
                }
            """ % {"backend": "127.0.0.1:8008"},
        },
        require=[Qubes("90-matrix-nginx"), Test("all certificates generated")],
        watch_in=[Service("nginx")],
    )
