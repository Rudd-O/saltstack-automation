#!objects

from salt://email/config.sls import config
from salt://lib/letsencrypt.sls import privkey_path, fullchain_path
from salt://lib/letsencrypt.sls import renewal_hook, restart_service_for_cert


include(".".join(sls.split(".")[:-1]) + ".service")

context = config["mta"]

if "tls_key_file" in context:
    Test.nop("certs ready")
else:
    assert context["hostname"] in pillar(
        "letsencrypt:hosts"
    ), f"Error: the hostname {context['hostname']} is not listed in pillar letsencrypt:hosts"
    include("letsencrypt")
    restart_service_for_cert("postfix", context["hostname"])
    renewal_hook("postfix", "restart")
    Test.nop("certs ready", require=[Test("all certificates generated")])
