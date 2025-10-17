#!objects


from salt://lib/qubes.sls import template, fully_persistent_or_physical


with Pkg.installed("nginx"):
    dropin = File.managed(
        "/etc/systemd/system/nginx.service.d/ulimits.conf",
        contents="""[Service]
LimitNOFILE=1048576
""",
        makedirs=True,
    ).requisite
daemonreload = Cmd.run(
    "Reload NginX service file",
    name="systemctl --system daemon-reload",
    onchanges=[dropin],
).requisite
svc = Qubes.enable_dom0_managed_service(
    "nginx",
    require=[daemonreload],
).requisite
deps = [svc]
dropin = [dropin]

if not template():
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
        name="nginx",
        watch=[File("/etc/nginx/nginx.conf")] + dropin,
        require=deps,
    )

    nginx_service = Service.running(
        "nginx",
        enable=True,
        require=[Service("nginx running in HTTP-only mode")],
    ).requisite

    Cmd.run(
        "reload nginx",
        name="systemctl --system reload nginx.service",
        onchanges=[Test.nop("noop state for reload nginx").requisite],
        require=[nginx_service],
    )
