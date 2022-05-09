#!objects

from salt://email/config.sls import config


slsp = sls.replace(".", "/")
context = config["mta"].get("dkim", {})
if "keys" not in context:
    context["keys"] = {}

with Pkg.installed("opendkim"):
    File.managed(
        "/etc/opendkim.conf",
        source=f"salt://{slsp}/opendkim.conf.j2",
        template="jinja",
        context={"config": context},
        mode="0644",
        watch_in=[Service("opendkim")],
    )
    File.directory(
        "/var/spool/opendkim/socket",
        mode="0750",
        user="opendkim",
        group="mail",
        watch_in=[Service("opendkim")],
    )
    for f in "KeyTable SigningTable".split():
        File.managed(
            f"/etc/opendkim/{f}",
            source=f"salt://{slsp}/{f}.j2",
            template="jinja",
            context=context,
            mode="0640",
            user="root",
            group="opendkim",
            watch_in=[Service("opendkim")],
        )
    for domain, privkey in context["keys"].items():
        File.managed(
            f"/etc/opendkim/keys/{domain}/default.private",
            contents=privkey,
            user="root",
            group="opendkim",
            mode="0640",
            require_in=[File("/etc/opendkim/KeyTable"), File("/etc/opendkim/SigningTable")],
            watch_in=[Service("opendkim")],
            makedirs=True,
        )

Service.running("opendkim", enable=True)
