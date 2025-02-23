#!objects

import os


from salt://lib/qubes.sls import template, physical
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path

include("nginx")
include("letsencrypt")


if grains("selinux:enabled"):
    Selinux.port_policy_present(
        "httpd_can_listen_to_8448",
        sel_type="http_port_t",
        protocol="tcp",
        port=8448,
        require_in=[Service("nginx")] if not template() else [],
    )
    Selinux.boolean(
        "httpd_can_network_relay for Matrix",
        name="httpd_can_network_relay",
        value=True,
        persist=True,
        require_in=[Service("nginx")] if not template() else [],
    )

if not template():
    synapse = pillar("matrix:synapse", {})
    delegated_hostname = synapse["delegated_hostname"]
    cert = fullchain_path(delegated_hostname)
    key = privkey_path(delegated_hostname)

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
                    # Long polling configuration.
                    proxy_buffering off;
                    proxy_request_buffering off;
                    keepalive_timeout   900s;
                    keepalive_requests  1000000;
                    proxy_read_timeout  900s;
                    proxy_send_timeout  900s;
                    send_timeout        900s;
                    proxy_ignore_client_abort off;
                    # End long polling configuration.

                    # note: do not add a path (even a single /) after the port in `proxy_pass`,
                    # otherwise nginx will canonicalise the URI and cause signature verification
                    # errors.
                    # DO NOT USE LOCALHOST, always use an IP address.
                    proxy_pass http://%(backend)s;
                    proxy_set_header X-Forwarded-For $remote_addr;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header Host $host;
                }
            """ % {"backend": "127.0.0.1:8008"},
        },
        require=[Qubes("90-matrix-nginx"), Test("all certificates generated")],
        onchanges_in=[Cmd("reload nginx")],
    )
