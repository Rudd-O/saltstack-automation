#!objects

from salt://build/repo/config.sls import config


context = config.client
reqs = []

if "rpm" in context and "base_url" in context.rpm:
    include(".rpm")
    reqs.append(Test("RPM repo deployed"))
if "docker" in context and "registry_url" in context.docker:
    include(".docker")
    reqs.append(Test("Docker repo deployed"))

Test.nop('repo deployed', require=reqs)
