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
        include("plone.ssl_termination.selinux")

    server_names = context.get("server_names", [context.get("server_name", None)])
    if server_names[0] == None:

        Test.fail_without_changes("The plone.ssl_termination formula requires a list of server_names or a server_name under pillar plone:ssl_termination.")

    else:

        for server_name in server_names:
            if hasattr(server_name, "items"):
                canonical = server_name["canonical"]
                server_name = server_name["name"]
            else:
                canonical = None

            cert = fullchain_path(server_name)
            key = privkey_path(server_name)

            redirect_config = f"""
                            rewrite ^/$ https://{canonical} permanent;
                            rewrite ^/(.*)$ https://{canonical}/$1 permanent;
""".strip()
            proxy_pass_config = f"""
                            # Varnish configuration.
                            proxy_buffering off;
                            proxy_request_buffering off;
                            # End Varnish configurations.

                            proxy_set_header X-Forwarded-For $remote_addr;
                            proxy_set_header X-Forwarded-Proto $scheme;
                            proxy_set_header Host $host;
                            proxy_pass http://{backend};
""".strip()

            if canonical:
                location_config = redirect_config
            else:
                location_config = proxy_pass_config

            File.managed(
                "/etc/nginx/conf.d/vhosts/%s.conf" % server_name,
                name="/etc/nginx/conf.d/vhosts/%s.conf" % server_name,
                source="salt://nginx/vhost.conf.j2",
                template="jinja",
                makedirs=True,

                context={
                    "ports": [443],
                    "server_name": server_name,
                    "max_upload_size": context.get("max_upload_size", "1000M"),
                    "ssl_certificate": cert,
                    "ssl_certificate_key": key,
                    "hsts": context.get("hsts", True),
                    "server_config": """
                        location / {
                            %(location_config)s
                        }
                    """ % locals(),
                },
                require=[Qubes("90-matrix-nginx"), Test("all certificates generated")],
                onchanges_in=[Cmd("reload nginx")],
            )
