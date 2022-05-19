#!objects

certbot_webroot = "/etc/letsencrypt/webroot"
certbot_live = "/etc/letsencrypt/live"
certbot_archive = "/etc/letsencrypt/archive"


import os
from shlex import quote


def fake_for(hostname):
    context = pillar("letsencrypt", {})
    default_fake = context.get("fake", False)
    data = context["hosts"][hostname]
    fake = data.get("fake", default_fake)
    return fake


def certificate_dir(hostname):
    return os.path.join(certbot_live, hostname)


def certificate_archive_dir(hostname):
    return os.path.join(certbot_archive, hostname)


def fullchain_path(hostname):
    return os.path.join(certificate_dir(hostname), "fullchain.pem")


def privkey_path(hostname):
    return os.path.join(certificate_dir(hostname), "privkey.pem")


def restart_service_for_cert(service, hostname):
    Service.running(
        extend(service), watch=[Cmd(f"generate certificate for {hostname}")]
    )


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


def allow_user(hostname, user, require=None):
    if not require:
        require = []

    privkey = privkey_path(hostname)
    quoted_user = quote(user)
    quoted_privkey = quote(privkey)
    archive_path = certificate_archive_dir(hostname)
    quoted_archive_path = quote(archive_path)

    pre = Cmd.run(
        f"Allow ACL for certificate of {hostname} as user {user}",
        name=f"setfacl -m u:{quoted_user}:r {quoted_privkey}",
        unless=f"getfacl {quoted_privkey} | grep -q ^user:{quoted_user}:r",
        require=[Cmd(f"generate certificate for {hostname}")] + require,
    ).requisite
    unless = f"getfacl {quoted_archive_path} | grep -q ^default:user:{quoted_user}:r-x"
    if fake_for(hostname):
        # Folder won't exist.
        unless = "true"
    post = Cmd.run(
        f"Allow default ACL for future certificates of {hostname} as user {user}",
        name=f"setfacl -m default:u:{quoted_user}:rx {quoted_archive_path}",
        unless=unless,
        require=[pre],
    ).requisite
    return pre, post
