#!objects

from salt://lib/qubes.sls import template
from salt://lib/defs.sls import SystemUserForContainers


username = "whiteboard"

u, localsharecontainers, containerbind, context_applied, subgid, subuid = SystemUserForContainers(
    username,
    shell="/sbin/nologin",
)

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
    environment_file="/etc/default/whiteboard",
    network="host",
    userns="keep-id",
    args=["--logs-dir=/tmp", "--verbose"],
    enable=True,
    runas=username,
    makedirs=True,
    require=[p] + [subuid, subgid] + [containerbind, context_applied],
).requisite

qubified = Qubes.enable_dom0_managed_service(
    "whiteboard qubified",
    name="whiteboard",
    require=[q],
    scope="user",
    enable=False,
).requisite

rld = Userservice.systemd_reload(
    f"daemon-reload for {sls}",
    user=username,
    onchanges=[q, qubified],
).requisite

if not template():
    domain = pillar("whiteboard:domain")
    jwt = pillar("whiteboard:jwt_secret_key")
    env = File.managed(
        "/etc/default/whiteboard",
        contents=f"""NEXTCLOUD_URL=https://{domain}
JWT_SECRET_KEY={jwt}""",
        onchanges_in=[rld],
        user="root",
        group="whiteboard",
        mode="0640",
    ).requisite
    lng = Userservice.linger(
        f"Linger {username}",
        user=username,
    ).requisite
    envbind = Qubes.bind_dirs(
        'whiteboard',
        directories=['/etc/default/whiteboard', f'/var/lib/systemd/linger/{username}'],
        require=[env, lng],
    ).requisite
    rn = Userservice.running(
        "whiteboard",
        user=username,
        enable=True,
        require=[rld, lng],
        watch=[q, env, envbind],
    )
