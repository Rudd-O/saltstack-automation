#!objects

import os

from salt://lib/qubes.sls import template
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path
from salt://build/repo/config.sls import config


include("nginx")
include("letsencrypt")

if not template():
    context = config.mirror
    root = context.paths.root

    with Qubes.bind_dirs(
        '90-build-repo-mirror',
        directories=[root],
    ):
        File.directory("Root directory for repo", name=root)

    server_names = context.get("server_names", [context.get("server_name", None)])
    if server_names[0] == None:

        Test.fail_without_changes("The build.repo.mirror formula requires a list of server_names or a server_name under pillar plone:ssl_termination.")

    else:

        for server_name in server_names:
            cert = fullchain_path(server_name)
            key = privkey_path(server_name)
            File.managed(
                "/etc/nginx/conf.d/vhosts/%s.conf" % server_name,
                name="/etc/nginx/conf.d/vhosts/%s.conf" % server_name,
                source="salt://nginx/vhost.conf.j2",
                template="jinja",
                makedirs=True,
                context={
                    "ports": [443],
                    "server_name": server_name,
                    "ssl_certificate": cert,
                    "ssl_certificate_key": key,
                    "hsts": context.get("hsts", True),
                    "server_config": """
                        location / {
                            root %(root)s;
                            autoindex on;
                        }
                    """ % locals(),
                },
                require=[
                    File("Root directory for repo"),
                    File("/etc/nginx/nginx.conf"),
                    Test("all certificates generated"),
                ],
                onchanges_in=[Cmd("reload nginx")],
            )
