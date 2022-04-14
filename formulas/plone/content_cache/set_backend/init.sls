#!objects

from salt://lib/qubes.sls import template, fully_persistent_or_physical


if fully_persistent_or_physical():
    Pkg.installed("python3-jinja2")
    Pkg.installed("python3-requests")
    pkgs = [Pkg("python3-jinja2"), Pkg("python3-requests")]
else:
    pkgs = []

if not template():
    File.managed(
        "/usr/local/bin/varnish-set-backend",
        source="salt://" + sls.replace(".", "/") + "/varnish-set-backend",
        mode="0755",
        require=pkgs,
    )
else:
    File.exists("/usr/local/bin/varnish-set-backend", require=pkgs)
