#!objects

from salt://lib/defs.sls import Perms
from salt://build/repo/config.sls import config

docker = config.server.docker
rpm = config.server.rpm
slsp = "/".join(sls.split("."))

include("nginx")

p = Pkg("nginx")
srv = Service("nginx")

se = Customselinux.policy_module_present(
    "nginxsamba",
    source=f"salt://{slsp}/nginxsamba.te",
    require=[p],
).requisite

old = File.absent("/etc/nginx/conf.d/repo.conf").requisite

File.managed(
    "/etc/nginx/conf.d/vhosts/repo.conf",
    source=f"salt://{slsp}/repo.conf.j2",
    makedirs=True,
    template="jinja",
    context={
        "rpm_basedir": rpm.paths.root,
        "rpm_hostname": rpm.vhost,
        "docker_address": docker.address,
        "docker_debug_address": docker.debug_address,
        "docker_hostname": docker.vhost,
        "docker_htpasswd": docker.paths.htpasswd,
    },
    require=[p, se, old],
    watch_in=[srv],
    **Perms.file
).requisite

Test.nop("Frontend deployed", require=[srv])
