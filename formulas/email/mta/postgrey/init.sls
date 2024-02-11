#!objects

from salt://email/config.sls import config


context = config.get("mta", {})
slsp = "/".join(sls.split("."))

if context["greylisting"]:
    greylisting = context["greylisting"]
    with Pkg.installed("postgrey"):
        Customselinux.policy_module_present(
            "postgreylocal",
            source="salt://" + "/".join(sls.split(".")) + "/postgreylocal.te",
            require_in=[Service("postgrey")],
        )
        svc = Service.running("postgrey", enable=True).requisite
    if hasattr(greylisting, "items"):
        whitelist_clients = greylisting.get("whitelist_clients", [])
        whitelist_recipients = greylisting.get("whitelist_recipients", [])
    else:
        whitelist_clients, whitelist_recipients = [], []
    File.managed(
        "/etc/postfix/postgrey_whitelist_clients.local",
        source=f"salt://{slsp}/postgrey_whitelist_clients.local.j2",
        template="jinja",
        context={
            "whitelist": whitelist_clients,
        },
        watch_in=[svc],
        require=[Pkg("postgrey")],
    )
    File.managed(
        "/etc/postfix/postgrey_whitelist_recipients",
        source=f"salt://{slsp}/postgrey_whitelist_recipients.j2",
        template="jinja",
        context={
            "whitelist": whitelist_recipients,
        },
        watch_in=[svc],
        require=[Pkg("postgrey")],
    )
else:
    with Service.dead("postgrey", enable=False):
        Pkg.removed("postgrey")
