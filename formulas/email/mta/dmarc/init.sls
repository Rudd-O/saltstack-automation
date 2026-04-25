#!objects

from salt://lib/defs.sls import ReloadSystemdOnchanges
from salt://email/config.sls import config


slsp = sls.replace(".", "/")
context = config["mta"]["dmarc"]

p = Pkg.installed("dmarc", pkgs=["opendmarc", "opendmarc-tools"]).requisite

rs = ReloadSystemdOnchanges(sls)

f = File.managed(
    "/etc/systemd/system/opendmarc.service.d/group.conf",
    contents="""[Service]
Group=
Group=mail
""",
    require=[p],
    onchanges_in=[rs],
    makedirs=True,
).requisite

c = File.managed(
    "/etc/opendmarc.conf",
    source=f"salt://{slsp}/opendmarc.conf.j2",
    template="jinja",
    context=context,
    mode="0644",
).requisite

Service.running("opendmarc", enable=True, watch=[f, c], require=[rs])
