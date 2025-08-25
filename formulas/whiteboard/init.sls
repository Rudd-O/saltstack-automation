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

version = pillar("whiteboard:version", "release")
if version:
    version = f":{version}"

q = Podman.quadlet_present(
    "whiteboard",
    image=f"ghcr.io/nextcloud-releases/whiteboard{version}",
    # Listen port is 3002
    environment=[
        f"NEXTCLOUD_URL=https://{domain}",
        f"JWT_SECRET_KEY={jwt}",
    ],
    network="host",
    userns="keep-id",
    args=["--logs-dir=/tmp", "--verbose"],
    enable=True,
    runas=username,
    makedirs=True,
    require=[p] + [subuid, subgid],
).requisite

rld = Userservice.systemd_reload(
    f"daemon-reload for {sls}",
    user=username,
    onchanges=[q],
).requisite

lng = Userservice.linger(
    f"Linger {username}",
    user=username,
).requisite

rn = Userservice.running(
    "whiteboard",
    user=username,
    enable=True,
    require=[rld, lng],
    watch=[q],
)
