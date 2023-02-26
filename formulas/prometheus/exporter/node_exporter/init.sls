#!objects

from salt://lib/qubes.sls import updateable, template, physical
from salt://prometheus/exporter/node_exporter/config.sls import config
from salt://build/repo/client/lib.sls import rpm_repo


include(sls + ".systemd")
daemonreload = Cmd("Reload systemd for node exporter")

debian = grains("os") in ("Debian", "Ubuntu")
name = "prometheus-node-exporter" if debian else sls.split(".")[-1]
slsp = sls.replace(".", "/")

include(sls + ".collectors")
tmpfiles_created = Test("Collector directory created")

if updateable():
    textfile_directory = config.paths.textfile_directory

    p = Mypkg.installed(
        f"{name}-pkg",
        name=name,
        require=[rpm_repo()],
        require_in=[] if template() else [File(textfile_directory)],
    ).requisite

    tmpfilesconf = File.absent(
        f"/etc/tmpfiles.d/{name}.conf",
    ).requisite

    svcenabled = Qubes.enable_dom0_managed_service(
        f"{name} enabled",
        name=name,
        require=[p],
    ).requisite

    wait_for_tmpfilesconf = File.absent(
        f"/etc/systemd/system/{name}.service.d/wait-for-tmpfiles.conf",
        watch_in=[daemonreload],
    ).requisite

    notimex = "" if physical() else "--no-collector.timex "
    OPTS = "ARGS" if debian else "NODE_EXPORTER_OPTS"
    conf = File.managed(
        f"/etc/default/{name}",
        contents=f"""
    {OPTS}='{notimex}--collector.nfs --collector.nfsd --collector.textfile --collector.textfile.directory={textfile_directory} --collector.logind --collector.filesystem.ignored-fs-types="^(nfs4|autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$"'
    """.lstrip(),
        require=[p],
    ).requisite

    svcwatch = [conf, wait_for_tmpfilesconf]
    svcrequire = [daemonreload, svcenabled, tmpfiles_created]
else:
    svcwatch = []
    svcrequire = [tmpfiles_created]

if not template():
    svcrunning = Service.running(
        name,
        watch=svcwatch,
        require=svcrequire,
    ).requisite
