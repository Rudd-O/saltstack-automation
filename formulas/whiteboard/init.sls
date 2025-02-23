#!objects


from salt://lib/qubes.sls import template, fully_persistent_or_physical
from salt://lib/defs.sls import Perms, SystemUser

username = "whiteboard"

u = SystemUser(
    username,
    shell="/sbin/nologin",
)

subgid = Podman.allocate_subgid_range(
    f"{username} subgid",
    name=username,
    howmany="1000000",
    require=[u],
).requisite

subuid = Podman.allocate_subuid_range(
    f"{username} subuid",
    name=username,
    howmany="1000000",
    require=[u],
).requisite

domain = pillar("whiteboard:domain")
jwt = pillar("whiteboard:jwt_secret_key")

p = Pkg.installed(
    "podman",
).requisite

Podman.present(
    "whiteboard",
    image=f"ghcr.io/nextcloud-releases/whiteboard:release",
    # Listen port is 3002
    options=[
        {"e": f"NEXTCLOUD_URL=https://{domain}"},
        {"e": f"JWT_SECRET_KEY={jwt}"},
        {"network": "host"},
        # {"cap-add": "MKNOD"},
        #{"subuidname": username},
        #{"subgidname": username},
        {"userns": "keep-id"},
        #{"security-opt": "unmask=/proc/*"},
    ],
    enable=True,
    runas=username,
    require=[p] + [subuid, subgid],
)
