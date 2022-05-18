#!objects

from salt://email/config.sls import config
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path


include(sls + ".service")
include(sls + ".tls")


slsp = sls.replace(".", "/")
context = config["mda"]
if context["enable"]:
    if "tls_key_file" in context:
        pass
    else:
        context["tls_key_file"] = privkey_path(context["hostname"])
        context["tls_cert_file"] = fullchain_path(context["hostname"])

    include(".sieve")


with Pkg.installed(
    "dovecot-pkg",
    pkgs=["openssl", "dovecot"],
    require_in=[Pkg("dovecot-pigeonhole")] if context["enable"] else [],
):
    File.managed(
        "/etc/dovecot/local.conf",
        source=f"salt://{slsp}/local.conf.j2",
        mode="0644",
        watch_in=[Service("dovecot")],
        template="jinja",
        context=context,
        require=[Test("dovecot certs ready")] + ([Test("sieve tooling deployed")] if context["enable"] else []),
    )
    Cmd.run(
        "create Diffie-Hellman SSL parameters file",
        name="openssl dhparam 2048 > /etc/dovecot/dh.pem && chmod 440 /etc/dovecot/dh.pem || rm -f /etc/dovecot/dh.pem",
        creates="/etc/dovecot/dh.pem",
        watch_in=[Service("dovecot")],
    )
