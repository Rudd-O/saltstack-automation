#!objects

include(sls + ".postgrey")

include(sls + ".dkim")

include(sls + ".postfix")

include(sls + ".spf")

include(sls + ".dovecot")

Service.running(
    extend("postfix"),
    require=[
        Service("postgrey"),
        Service("opendkim"),
        Service("dovecot"),
        File("/etc/python-policyd-spf/policyd-spf.conf"),
    ],
)
