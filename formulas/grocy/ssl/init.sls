#!objects

import os


from salt://lib/qubes.sls import template
from salt://lib/internal_ssl.sls import internal_ssl_vhost, proxy_pass_config_template
from salt://lib/selinux_objects.sls import nginx_connect_port_policy

include("nginx")


if not template():
    config = pillar(sls.split(".")[0], {})
    hostname = config["ssl"]["server_name"]
    cert = config["ssl"]["certificate"]
    key = config["ssl"]["key"]

    proxy_pass_config = """
        try_files $uri /index.php;
    }

    location ~ \\.php$ {
        fastcgi_split_path_info ^(.+\\.php)(/.+)$;
        fastcgi_pass unix:/run/php-fpm/grocy.sock;
        fastcgi_index index.php;
        include fastcgi.conf;
    """
    internal_ssl_vhost(hostname, cert, key, proxy_pass_config, root="/usr/share/grocy/public")
