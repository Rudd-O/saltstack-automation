#!objects

from salt://email/config.sls import config


include(".".join(sls.split(".")[:-1]) + ".mta.postfix.virtual")
include(".".join(sls.split(".")[:-1]) + ".dovecot")
include(sls + ".accounts")

Test.nop(
    extend("All local recipients created"),
    require_in=[File("/etc/postfix/virtual")],
)
