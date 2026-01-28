#!objects


from salt://lib/qubes.sls import template
from salt://lib/defs.sls import SystemUserForContainers

username = "collabora"

"""
Podman.present(
    "collabora-code",
    image=f"registry.hub.docker.com/collabora/code{version}",
    options=[
        {"e":
            "extra_params=--o:ssl.enable=false"
            " --o:ssl.termination=true"
            " --o:net.service_root=/collabora"
        },
        {"network": "host"},
        {"cap-add": "MKNOD"},
        #{"subuidname": username},
        #{"subgidname": username},
        #{"security-opt": "unmask=/proc/*"},
    ],
    enable=True,
#    runas=username,
    require=[p], #, subuid, subgid],
)
"""

username = "collabora"

u, localsharecontainers, containerbind, context_applied, subgid, subuid = SystemUserForContainers(
    username,
    shell="/sbin/nologin",
)

p = Pkg.installed(
    "podman",
).requisite

version = pillar('collabora:version')
if version:
    version = f":{version}"

q = Podman.quadlet_present(
    "collabora",
    image=f"registry.hub.docker.com/collabora/code{version}",
    environment_file="/etc/default/collabora",
    network="host",
    userns="keep-id",
    args=[],
    enable=True,
    runas=username,
    makedirs=True,
    require=[p] + [subuid, subgid] + [containerbind, context_applied],
).requisite

qubified = Qubes.enable_dom0_managed_service(
    "collabora qubified",
    name="collabora",
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
    env = File.managed(
        "/etc/default/collabora",
        contents=f"""extra_params=--o:ssl.enable=false --o:ssl.termination=true --o:net.service_root=/collabora
""",
        user="root",
        group=username,
        mode="0640",
        require=[u],
    ).requisite
    lng = Userservice.linger(
        f"Linger {username}",
        user=username,
        require=[u],
    ).requisite
    envbind = Qubes.bind_dirs(
        'collabora',
        directories=['/etc/default/collabora', f'/var/lib/systemd/linger/{username}'],
        require=[env, lng],
    ).requisite
    rn = Userservice.running(
        "collabora",
        user=username,
        enable=True,
        require=[rld, lng],
        watch=[q, env, envbind],
    )
