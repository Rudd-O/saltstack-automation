#!objects

from salt://email/config.sls import config
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path
from salt://lib/letsencrypt.sls import renewal_hook


include(".".join(sls.split(".")[:-1]) + ".service")

slsp = "/".join(sls.split(".")[:])

context = config["mta"]

if "tls_key_file" in context:
    pass
else:
    context["tls_key_file"] = privkey_path(context["hostname"])
    context["tls_cert_file"] = fullchain_path(context["hostname"])

Cmd.run(
    "Set up aliases database",
    name="""
set -e
aliasesmodtime=$(stat -c %Y /etc/aliases || echo 0)
aliasesdbmodtime=$(stat -c %Y /etc/aliases.db || echo 0)

if [ "$aliasesmodtime" = "0" ] ; then
    echo changed=no comment='"The file /etc/aliases is absent."'
    exit 0
fi

if [ "$aliasesmodtime" -lt "$aliasesdbmodtime" ] ; then
    echo changed=no comment='"The file /etc/aliases.db is up to date."'
    exit 0
fi

newaliases

echo
echo changed=yes comment='"The file /etc/aliases.db has been updated."'
""",
    stateful=True,
    require_in=[File("/etc/postfix/main.cf")],
    require=[Pkg("postfix-pkg")],
)

for f in ["main.cf", "master.cf"]:
    File.managed(
        f"/etc/postfix/{f}",
        source=f"salt://{slsp}/{f}.j2",
        template="jinja",
        context=context,
        require=[Pkg("postfix-pkg")],
        watch_in=[Service("postfix")],
    )
