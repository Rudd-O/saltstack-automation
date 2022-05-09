#!objects

include(".".join(sls.split(".")[:-1]) + ".postfix.service")

Pkg.installed("pypolicyd-spf")

slsp = sls.replace(".", "/")

from salt://email/config.sls import config

User.present(
    "policyd-spf user",
    name="policyd-spf",
    system=True,
    usergroup=True,
    shell="/sbin/nologin",
    home="/var/lib/policyd-spf",
)

context = config["mta"]["spf"]

File.managed(
    "/etc/python-policyd-spf/policyd-spf.conf",
    source=f"salt://{slsp}/policyd-spf.conf.j2",
    template="jinja",
    context=context,
    require=[Pkg("pypolicyd-spf"), User("policyd-spf user")],
    watch_in=[Service("postfix")],
)
