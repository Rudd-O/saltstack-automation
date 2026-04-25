#!objects

include(sls + ".postgrey")

include(sls + ".dkim")

include(sls + ".postfix")

include(sls + ".spf")

include(sls + ".dmarc")

include(".".join(sls.split(".")[:-1]) + ".dovecot")

Service.running(
    extend("postfix"),
    require=[
        Service("postgrey"),
        Service("opendkim"),
        Service("dovecot"),
        Service("opendmarc"),
        File("/etc/python-policyd-spf/policyd-spf.conf"),
    ],
)
