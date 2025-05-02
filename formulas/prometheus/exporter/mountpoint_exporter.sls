#!objects

from salt://lib/qubes.sls import updateable
from salt://build/repo/client/lib.sls import rpm_repo


name = sls.split(".")[-1]

if updateable():
    p = Mypkg.installed(
        f"{name}-pkg",
        name=name,
        require=[rpm_repo()],
    ).requisite
else:
    p = Test.nop(f"{name}-pkg").requisite

svcrunning = Service.running(
    name,
    watch=p,
    enable=True,
).requisite
