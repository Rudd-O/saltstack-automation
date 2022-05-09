#!objects

include(sls + ".postgrey")

include(sls + ".dkim")

include(sls + ".postfix")

include(sls + ".spf")

Service.running(
    extend("postfix"),
    require=[
        Service("postgrey"),
        Service("opendkim"),
        File("/etc/python-policyd-spf/policyd-spf.conf"),
    ],
)
