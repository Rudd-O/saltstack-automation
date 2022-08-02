#!objects

from salt://lib/qubes.sls import updateable, template


if updateable():
    include("build.repo.client.rpm")
    with Mypkg.installed("needs-restart", require=[Test("RPM repo deployed")]):
        milestone = Test.nop("needs-restart deployed")
else:
    milestone = Test.nop("needs-restart deployed")
