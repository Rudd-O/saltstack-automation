certbot_webroot = "/etc/letsencrypt/webroot"
certbot_live = "/etc/letsencrypt/live"


import os


def certificate_dir(hostname):
    return os.path.join(certbot_live, hostname)


def fullchain_path(hostname):
    return os.path.join(certificate_dir(hostname), "fullchain.pem")


def privkey_path(hostname):
    return os.path.join(certificate_dir(hostname), "privkey.pem")
