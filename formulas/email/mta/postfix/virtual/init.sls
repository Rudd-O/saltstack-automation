#!objects

from salt://email/config.sls import config


context = config.get("mda", {})
slsp = "/".join(sls.split("."))

include(".".join(sls.split(".")[:-1]) + ".config")

File.managed(
    f"/etc/postfix/virtual",
    source=f"salt://{slsp}/virtual.j2",
    template="jinja",
    context=context,
    require=[
        Pkg("postfix-pkg"),
        File("/etc/postfix/main.cf"),
    ],
)

oc = {"onchanges": [File("/etc/postfix/virtual")]} if __salt__["file.file_exists"]("/etc/postfix/virtual.db") else {} 
Cmd.run(
    "postmap /etc/postfix/virtual",
    require=[File("/etc/postfix/virtual")],
    watch_in=[Service("postfix")],
    **oc,
)
