#!objects

certbot_webroot = "/etc/letsencrypt/webroot"
certbot_live = "/etc/letsencrypt/live"


import os


def certificate_dir(hostname):
    return os.path.join(certbot_live, hostname)


def fullchain_path(hostname):
    return os.path.join(certificate_dir(hostname), "fullchain.pem")


def privkey_path(hostname):
    return os.path.join(certificate_dir(hostname), "privkey.pem")


def renewal_hook(service, mode="reload"):
    global File
    global Service
    default_fake = pillar("letsencrypt:fake", False)
    fakes = [
        data.get("fake", default_fake) for data in pillar("letsencrypt:hosts").values()
    ]
    if all(fakes):
        File.absent(
            f"/etc/letsencrypt/renewal-hooks/post/{service}",
            require=[Service(service)],
        )
    else:
        # Create renewal hook to restart service.
        File.managed(
            f"/etc/letsencrypt/renewal-hooks/post/{service}",
            contents=f"""
#!/bin/bash -e
systemctl {mode} {service}.service
            """.strip(),
            mode="0755",
            makedirs=True,
            require=[Service(service)],
        )
