#!objects


from salt://lib/qubes.sls import template, fully_persistent_or_physical
from salt://lib/defs.sls import Perms, SystemUser

username = "collabora"

"""
u = SystemUser(
    username,
    shell="/sbin/nologin",
)

subgid = Podman.allocate_subgid_range(
    f"{username} subgid",
    name=username,
    howmany="200000",
    require=[u],
).requisite

subuid = Podman.allocate_subuid_range(
    f"{username} subuid",
    name=username,
    howmany="200000",
    require=[u],
).requisite
"""
domain = pillar("collabora:domain")

p = Pkg.installed(
    "podman",
).requisite

Podman.present(
    "collabora-code",
    image=f"registry.hub.docker.com/collabora/code",
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

Podman.present(
    "collabora-code",
    image=f"registry.hub.docker.com/collabora/code",
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
