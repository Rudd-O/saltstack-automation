#!objects

from salt://build/repo/config.sls import config
from salt://lib/defs.sls import Perms


include(".fileserver")
include(".mirrorer")


context = config.mirror
perms = Perms("mirrorer")

milestone = Test.nop("mirror deployed").requisite

File.directory(
    "Permissions for repo directory",
    name=context.paths.root,
    require=[
        File("Root directory for repo"),
        User("mirrorer"),
        File("/usr/local/bin/mirrorersh"),
        Cmd("reload nginx"),
        SshAuth("access to mirrorer"),
    ],
    require_in=[milestone],
    **perms.dir,
)
