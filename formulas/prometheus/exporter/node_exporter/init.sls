#!objects

from shlex import quote
from textwrap import dedent

from salt://lib/qubes.sls import updateable, template, physical
from salt://prometheus/exporter/node_exporter/config.sls import config
from salt://lib/defs.sls import ReloadSystemdOnchanges, SystemdSystemDropin
from salt://build/repo/client/lib.sls import rpm_repo


include(sls + ".systemd")
daemonreload = ReloadSystemdOnchanges(sls)

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
    ).requisite

    qmake = quote(f"mkdir -p {quote(textfile_directory)} && chmod 0750 {quote(textfile_directory)} && chgrp prometheus {quote(textfile_directory)}")
    collector_dir_maker = File.managed(
        "/etc/systemd/system/node_exporter-collector.service",
        contents=dedent(f"""\
            [Unit]
            Description=Create the node exporter collector folder
            
            [Service]
            Type=oneshot
            RemainAfterExit=true
            ExecStart=/usr/bin/bash -c {qmake}

            [Install]
            WantedBy=node_exporter.service
            """),
        mode="0644",
        onchanges_in=[daemonreload],
        require=[p]
    ).requisite

    collectorcreate = Service.running(
        "node_exporter-collector",
        enable=True,
        watch=[collector_dir_maker],
        require=[daemonreload],
        require_in=[tmpfiles_created],
    )

    collectorwait, collectorwait_reload = SystemdSystemDropin(
        "node_exporter",
        "wait-for-collector",
        contents=dedent("""\
            [Unit]
            After=node_exporter-collector.service
            """),
        require=[collector_dir_maker],
    )

    olddir = File.absent(
        "/var/lib/node_exporter",
        require=[collectorwait],
    ).requisite

    tmpfilesconf = File.absent(
        f"/etc/tmpfiles.d/{name}.conf",
    ).requisite

    svcdisabled = Qubes.disable_dom0_managed_service(
        f"{name} disqubified",
        name=name,
        require=[p],
    ).requisite

    wait_for_tmpfilesconf = File.absent(
        f"/etc/systemd/system/{name}.service.d/wait-for-tmpfiles.conf",
        onchanges_in=[daemonreload],
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

    svcwatch = [conf, wait_for_tmpfilesconf, olddir, collector_dir_maker, collectorwait]
    svcrequire = [daemonreload, svcdisabled, tmpfiles_created, collectorwait_reload]
else:
    svcwatch = []
    svcrequire = [tmpfiles_created]

svcrunning = Service.running(
    name,
    watch=svcwatch,
    require=svcrequire,
    enable=True,
).requisite
