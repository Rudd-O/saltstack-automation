#!objects


from salt://lib/qubes.sls import rw_only_or_physical, fully_persistent_or_physical


if fully_persistent_or_physical():
    with Pkg.installed("nginx"):
        Qubes.enable_dom0_managed_service("nginx")
    deps = [Qubes("nginx")]
else:
    deps = []

if rw_only_or_physical():
    certbot_webroot = "/etc/letsencrypt/webroot"

    Qubes.bind_dirs(
        '90-matrix-nginx',
        directories=['/etc/nginx'],
        require=deps,
    )

    File.managed(
        "/etc/nginx/nginx.conf",
        source="salt://nginx/nginx.conf.j2",
        template="jinja",
        context={
            "certbot_webroot": certbot_webroot,
        },
        require=[Qubes("90-matrix-nginx")],
    )

    Service.running(
        "nginx running in HTTP-only mode",
        watch=[
            File("/etc/nginx/nginx.conf"),
        ],
        require=deps,
    )

    Service.running(
        "nginx",
        enable=True,
        require=[Service("nginx running in HTTP-only mode")],
    )
