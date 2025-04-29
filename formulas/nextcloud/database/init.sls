#!objects

from salt://lib/qubes.sls import template, fully_persistent_or_physical


include("mariadb")
if not template():
    include(f"{sls}.dataenv")
    Test.nop(
        extend("Database setup"),
        require_in=[Test("Nextcloud database environment not yet defined")],
    )
