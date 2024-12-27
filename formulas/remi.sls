#!objects

from salt://lib/qubes.sls import fully_persistent_or_physical, dom0, physical


osrelease = grains("osrelease")

# to make the following work with TemplateVMs we have to set a proxy for Pkg.installed.
# but there is no proxy for it.  maybe env vars can be piped through?
#def _proxy():
#    if template():
#        proxy = "http://127.0.0.1:8082/"
#    else:
#        proxy = ""
#    return proxy
#
#export https_proxy=""" + _proxy() + """
#export http_proxy=""" + _proxy() + """


if fully_persistent_or_physical() and not dom0():
    if physical():
        free = Pkg.installed(
            "remi-release",
            sources=[
                {"remi-release": f"https://rpms.remirepo.net/fedora/remi-release-{osrelease}.rpm"},
            ],
        ).requisite
    else:
        # FIXME this doesn't actually install the RPMFusion packages.
        free = Pkg.installed("remi-release").requisite
    Test.nop("Remirepo setup", require=[free])
else:
    Cmd.wait("echo nothing to do")
