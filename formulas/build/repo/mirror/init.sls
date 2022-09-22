#!objects

from salt://build/repo/config.sls import config
from salt://lib/defs.sls import Perms


include(".fileserver")
include(".mirrorer")


context = config.mirror
perms = Perms("mirrorer")

milestone = Test.nop("mirror deployed").requisite

perms = File.directory(
    "Permissions for repo directory",
    name=context.paths.root,
    require=[
        File("Root directory for repo"),
        User("mirrorer"),
        File("/usr/local/bin/mirrorersh"),
        Cmd("reload nginx"),
        SshAuth("access to mirrorer"),
    ],
    dir_mode="0755",
    file_mode="0644",
    recurse=["user", "group", "mode"],
    **perms.dir,
).requisite

policy = Selinux.fcontext_policy_present(
    "SELinux context for repo directory",
    name=context.paths.root + "(/.*)?",
    sel_type=context.selinux_repo_context,
    require=[perms],
).requisite

Selinux.fcontext_policy_applied(
    "SELinux context applied",
    name=context.paths.root,
    recursive=True,
    require_in=[milestone],
    require=[policy],
)
