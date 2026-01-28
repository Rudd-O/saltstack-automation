#!objects

from salt://lib/qubes.sls import template, fully_persistent_or_physical


with Pkg.installed("valkey"):
    q = Qubes.enable_dom0_managed_service("valkey").requisite
deps = [q]

t = Test.nop("Redis setup", require=deps).requisite

if not template():
    b = Qubes.bind_dirs(
        '90-valkey',
        directories=['/var/lib/valkey'],
        require=deps,
    ).requisite
    s = Service.running(
        "valkey",
        enable=True,
        watch=[b],
        require_in=[t],
    ).requisite
