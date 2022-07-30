#!objects

from salt://build/repo/config.sls import config
from salt://lib/defs.sls import Perms, SystemUser, SSHAccessToUser


context = config.mirror
root = context.paths.root
keys = context.authorized_keys
slsp = "/".join(sls.split(".")[:-1])

shell = File.managed(
    "/usr/local/bin/mirrorersh",
    source="salt://{slsp}/mirrorersh.j2",
    context={"root": root},
    **Perms.dir,
).requisite

u = SystemUser(
    "mirrorer",
    shell="/usr/local/bin/mirrorersh",
    require=[File("/usr/local/bin/mirrorersh")],
)

a = SSHAccessToUser(
    "mirrorer",
    context.authorized_keys,
    require=[u],
)
