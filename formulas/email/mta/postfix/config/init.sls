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

for f in ["main.cf", "master.cf"]:
    File.managed(
        f"/etc/postfix/{f}",
        source=f"salt://{slsp}/{f}.j2",
        template="jinja",
        context=context,
        require=[
            Pkg("postfix-pkg"),
        ],
        watch_in=[Service("postfix")],
    )
