#!objects

from salt://email/config.sls import config


context = config.get("mda", {})

include(".".join(sls.split(".")[:-1]) + ".service")

Test.nop("before /etc/aliases")

catchall_username = context.get("catchall_username")
if catchall_username:
    File.line(
        "/etc/aliases without commented catchall",
        name="/etc/aliases",
        match="^#root:.*",
        mode="delete",
        require=[Test("before /etc/aliases")],
        onchanges_in=[Cmd("newaliases")],
    )
    File.replace(
        "/etc/aliases",
        name="/etc/aliases",
        pattern="^root:.*",
        repl="root:\t\t" + context["catchall_username"],
        append_if_not_found=True,
        count=1,
        require=[File("/etc/aliases without commented catchall")]
    )
else:
    File.comment(
        "/etc/aliases",
        regex="^root:.*",
        char="#",
        require=[Test("before /etc/aliases")],
    )

oc = (
    {"onchanges": [File("/etc/aliases")]}
    if __salt__["file.file_exists"]("/etc/aliases.db")
    else {}
)
Cmd.run(
    "newaliases",
    require=[File("/etc/aliases")],
    watch_in=[Service("postfix")],
    **oc,
)
