#!objects

include(sls + ".postgrey")

include(sls + ".dkim")

include(sls + ".postfix")

include(sls + ".spf")

include(".".join(sls.split(".")[:-1]) + ".dovecot")

Service.running(
    extend("postfix"),
    require=[
        Service("postgrey"),
        Service("opendkim"),
        Service("dovecot"),
        File("/etc/python-policyd-spf/policyd-spf.conf"),
    ],
)
