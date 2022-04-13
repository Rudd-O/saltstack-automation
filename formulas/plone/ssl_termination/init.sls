#!objects

import os


from salt://lib/qubes.sls import template, physical
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path

include("nginx")
include("letsencrypt")


if not template():
    context = pillar(sls.replace(".", ":"), {})
    backend = context.get("backend", "127.0.0.1:6081")

    if physical():
        Selinux.boolean(
            "httpd_can_network_relay for Plone",
            name="httpd_can_network_relay",
            value=True,
            require_in=[Service("nginx")],
        )

    server_names = context.get("server_names", [context.get("server_name", "None")])
    if server_names[0] == None:

        Test.fail_without_changes("The plone.ssl_termination formula requires a list of server_names or a server_name under pillar plone:ssl_termination.")

    else:

        for server_name in server_names:
            if server_name.startswith("www.") and server_name[4:] in server_names:
                # This is probably a www.example.org / example.org
                # certificate. Proceed as-is with the same certificate
                # as for the domain name.
                domain_name = server_name[4:]
            else:
                domain_name = server_name

            cert = fullchain_path(domain_name)
            key = privkey_path(domain_name)
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
                    "hsts": context.get("hsts", True),
                    "server_config": """
                        location / {
                            # Varnish configuration.
                            proxy_buffering off;
                            proxy_request_buffering off;
                            # End Varnish configurations.

                            proxy_set_header X-Forwarded-For $remote_addr;
                            proxy_set_header X-Forwarded-Proto $scheme;
                            proxy_set_header Host $host;
                            proxy_pass http://%(backend)s;
                        }
                    """ % locals(),
                },
                require=[Qubes("90-matrix-nginx"), Test("all certificates generated")],
                onchanges_in=[Cmd("reload nginx")],
            )
