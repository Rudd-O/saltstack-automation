#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical


if dom0():
    Test.fail_without_changes("Qubes dom0s are not upgradable via this method.")
elif fully_persistent_or_physical():
    include(f"{sls}.prepare")
    include(f"{sls}.upgrade")
    include(f"{sls}.cleanup")

    Test.nop(extend("Preupgrade"), require=[Test("Preparation complete")])
    Test.nop(extend("Postupgrade"), require_in=[Test("Cleanup begun")])
else:
    Test.fail_without_changes("This VM is not to be upgraded.")
