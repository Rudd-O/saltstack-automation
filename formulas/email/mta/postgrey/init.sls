#!objects

from salt://email/config.sls import config


context = config.get("mta", {})

if context["greylisting"]:
    with Pkg.installed("postgrey"):
        Customselinux.policy_module_present(
            "postgreylocal",
            source="salt://" + "/".join(sls.split(".")) + "/postgreylocal.te",
            require_in=[Service("postgrey")],
        )
        Service.running("postgrey", enable=True)
else:
    with Service.dead("postgrey", enable=False):
        Pkg.removed("postgrey")
