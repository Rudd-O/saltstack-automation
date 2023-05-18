#!objects

from salt://lib/defs.sls import ReloadSystemdOnchanges
from salt://email/config.sls import config


context = config["mta"]

include(".".join(sls.split(".")[:-1]) + ".package")

rs = ReloadSystemdOnchanges(sls)

if context.suppress_unresolvable_hostname_warning_logs:
    f = File.managed(
        "/etc/systemd/system/postfix.service.d/filterlogs.conf",
        contents="""
[Service]
LogFilterPatterns=~warning: hostname.*does not resolve to address.*Name or service not known
""".lstrip(),
        onchanges_in=[rs],
        require=Pkg("postfix-pkg"),
        makedirs=True,
    ).requisite
else:
    f = File.absent(
        "/etc/systemd/system/postfix.service.d/filterlogs.conf",
        onchanges_in=[rs],
        require=Pkg("postfix-pkg"),
    ).requisite

Service.running("postfix", enable=True, require=[rs], watch=[f])
