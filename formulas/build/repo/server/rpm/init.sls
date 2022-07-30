#!objects

from salt://build/repo/config.sls import config
from salt://lib/defs.sls import SystemUser, SSHAccessToUser, SSHKeyForUser, KnownHostForUser, Perms


context = config.server.rpm

p = Pkg.installed("createrepo_c").requisite

include(sls + ".artifactsh")

u = SystemUser(
    "artifact-pusher",
    shell="/usr/local/bin/artifactsh",
    require=[File("/usr/local/bin/artifactsh")],
)

a = SSHAccessToUser(
    "artifact-pusher",
    context.authorized_keys,
    require=[u],
)

_, h = KnownHostForUser(
    "artifact-pusher",
    context.mirror.host,
    context.mirror.known_host_keys,
    require=[u],
)

k = SSHKeyForUser(
    "artifact-pusher",
    key=context.mirror.privkey,
    require=[u],
)

root = File.directory(
    context.paths.root,
    selinux={"setype": context.setype},
    user="artifact-pusher",
    mode="0755",
    require=[u],
).requisite

Test.nop(
    "RPM repo server deployed",
    require=[root, k, h, a, p],
)
