#!objects

p = Pkg.installed(
    f"podman for SELinux contexts",
    pkgs=["podman"],
).requisite

contexts_needed = Cmd.run(
    f"Verify user container contexts need to be created",
    name=(
        "semanage fcontext -l | grep  '^/var/lib/[[][x^]/../'..local/share/containers/storage && echo changed=no || echo changed=yes"
        if not pillar("force_selinux_contexts")
        else "echo changed=yes"
    ),
    stateful=True,
    require=[p],
).requisite

contexts_present = []
for n, (path_re, setype) in enumerate([
    ('/var/lib/[^/]+/\\.local/share/containers/storage/artifacts(/.*)?', 'container_ro_file_t'),
    ('/var/lib/[^/]+/\\.local/share/containers/storage/overlay(/.*)?', 'container_ro_file_t'),
    ('/var/lib/[^/]+/\\.local/share/containers/storage/overlay-containers(/.*)?', 'container_ro_file_t'),
    ('/var/lib/[^/]+/\\.local/share/containers/storage/overlay-images(/.*)?', 'container_ro_file_t'),
    ('/var/lib/[^/]+/\\.local/share/containers/storage/overlay-layers(/.*)?', 'container_ro_file_t'),
    ('/var/lib/[^/]+/\\.local/share/containers/storage/overlay2(/.*)?', 'container_ro_file_t'),
    ('/var/lib/[^/]+/\\.local/share/containers/storage/overlay2-containers(/.*)?', 'container_ro_file_t'), 
    ('/var/lib/[^/]+/\\.local/share/containers/storage/overlay2-images(/.*)?', 'container_ro_file_t'), 
    ('/var/lib/[^/]+/\\.local/share/containers/storage/overlay2-layers(/.*)?', 'container_ro_file_t'),
    ('/var/lib/[^/]+/\\.local/share/containers/storage/volumes/[^/]*/.*', 'container_file_t'),
    ('/var/lib/[^/]+/\\.cache/containers(/.*)?', 'container_var_lib_t'),
]):
    contexts_present.append(
        Selinux.fcontext_policy_present(
            f"Set up SELinux contexts for user containers at {n}",
            name=path_re,
            filetype="a",
            sel_user="system_u",
            sel_type=setype,
            onchanges=[contexts_needed],
        ).requisite
    )

Test.nop("User containers experienced SELinux changes", watch=contexts_present + [contexts_needed]).requisite
