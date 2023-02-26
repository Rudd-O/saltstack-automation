#!objects

from salt://lib/qubes.sls import updateable, template
from salt://build/repo/client/lib.sls import rpm_repo


if updateable():
    with Mypkg.installed("needs-restart", require=[rpm_repo()]):
        milestone = Test.nop("needs-restart deployed")
else:
    milestone = Test.nop("needs-restart deployed")
