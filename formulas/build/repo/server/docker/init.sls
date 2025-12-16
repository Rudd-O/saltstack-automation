#!objects

import os

from salt://build/repo/config.sls import config


slsp = sls.replace(".", "/")
context = config.server.docker

include(sls + ".accounts")

with Test("docker-distribution accounts managed"):
    milestone = Test.nop("Docker repo server deployed").requisite

pkg = Pkg.installed(
  "docker-distribution pkg", name="docker-distribution"
).requisite

reloads = Cmd.wait("reload systemd", name="systemctl --system daemon-reload").requisite

svc = Service.running(
  "docker-distribution",
  enable=True,
  watch=[pkg],
  require=[reloads],
  require_in=[milestone],
).requisite

Pkg.installed("reg", require_in=[milestone])

root = File.directory(context.paths.root).requisite

if context.address.startswith("unix:"):

    sdir = File.directory(
        "docker-distribution socket directory",
        name=os.path.dirname(context.address[5:]),
        user="root",
        group="nginx",
        watch_in=[svc],
    ).requisite

    dir = os.path.dirname(context.address[5:])
    # Permit only nginx to connect to it.
    tmpfilesd = File.managed(
        "/etc/tmpfiles.d/docker-distribution.conf",
        contents=f"""
d {dir} 0750 registry nginx
    """.strip(),
        require=[sdir],
    ).requisite

    # Permit nginx to connect to it.
    File.managed(
      "/etc/systemd/system/docker-distribution.service.d/umask.conf",
      contents="""
[Unit]
After=systemd-tmpfiles.setup.service

[Service]
UMask=0000
  """.strip(),
        makedirs=True,
        require=[tmpfilesd],
        watch_in=[svc, reloads],
    )

else:

    File.absent(
        "docker-distribution socker directory",
        watch_in=[svc],
    )
    File.absent(
        "/etc/tmpfiles.d/docker-distribution.conf",
        require_in=[milestone],
    )

    File.absent(
        "/etc/systemd/system/docker-distribution.service.d/umask.conf",
        watch_in=[svc, reloads],
    )

File.managed(
    "/etc/docker-distribution/registry/config.yml",
    source=f"salt://{slsp}/config.yml.j2",
    template="jinja",
    context=context,
    require=[pkg, root],
    watch_in=[svc],
)
