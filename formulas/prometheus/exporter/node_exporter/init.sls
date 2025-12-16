#!objects

from shlex import quote
from textwrap import dedent

from salt://lib/qubes.sls import updateable, template, physical, dom0
from salt://prometheus/exporter/node_exporter/config.sls import config
from salt://lib/defs.sls import ReloadSystemdOnchanges, SystemdSystemDropin
from salt://build/repo/client/lib.sls import rpm_repo


daemonreload = ReloadSystemdOnchanges(sls)

debian = grains("os") in ("Debian", "Ubuntu")
name = "prometheus-node-exporter" if debian else "node-exporter"
slsp = sls.replace(".", "/")

include(sls + ".collectors")

textfile_directory = config.paths.textfile_directory

if updateable():
    oldp = Mypkg.removed(
        "node_exporter"
    ).requisite
    p = Mypkg.installed(
        f"{name}-pkg",
        name=name if not dom0() else "golang-github-prometheus-node-exporter",
        require=[rpm_repo(), oldp],
    ).requisite
else:
    p = Test.nop(f"{name}-pkg").requisite

qmake = quote(f"mkdir -p {quote(textfile_directory)} && chmod 0750 {quote(textfile_directory)} && chgrp prometheus {quote(textfile_directory)}")

obsolete_collector_service = Service.dead("node_exporter-collector", enable=False).requisite
obsolete_collector_file = File.absent("/etc/systemd/system/node_exporter-collector.service", require=[obsolete_collector_service], onchanges_in=[daemonreload]).requisite
collector_dir_maker = File.managed(
    "/etc/systemd/system/prometheus-node-exporter-collector.service",
    contents=dedent(f"""\
        [Unit]
        Description=Create the node exporter collector folder
        
        [Service]
        Type=oneshot
        RemainAfterExit=true
        ExecStart=/usr/bin/bash -c {qmake}

        [Install]
        WantedBy=prometheus-node-exporter.service
        """),
    mode="0644",
    onchanges_in=[daemonreload],
    require=[p, obsolete_collector_file]
).requisite

collectorcreate = Service.running(
    "prometheus-node-exporter-collector",
    enable=True,
    watch=[collector_dir_maker],
    require=[daemonreload],
    require_in=[Test("Collector directory created")],
)

old_dropin = File.absent("/etc/systemd/system/node_exporter.service.d", onchanges_in=[daemonreload], require=[p]).requisite

collectorwait, collectorwait_reload = SystemdSystemDropin(
    "prometheus-node-exporter",
    "wait-for-collector",
    contents=dedent("""\
        [Unit]
        After=node_exporter-collector.service
        """),
    require=[collector_dir_maker, old_dropin],
)

tmpfilesconf = File.absent(
    f"/etc/tmpfiles.d/{name}.conf",
).requisite

svcdisabled = Qubes.disable_dom0_managed_service(
    f"{name} disqubified",
    name=name,
    require=[p],
).requisite

wait_for_tmpfilesconf = File.absent(
    f"/etc/systemd/system/prometheus-node-exporter.service.d/wait-for-tmpfiles.conf",
    onchanges_in=[daemonreload],
).requisite

notimex = "" if physical() else "--no-collector.timex "
conf = File.managed(
    f"/etc/default/prometheus-node-exporter",
    contents=f"""
ARGS='{notimex}--collector.nfs --collector.nfsd --collector.textfile --collector.textfile.directory={textfile_directory} --collector.logind --collector.filesystem.ignored-fs-types="^(nfs4|autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$"'
""".lstrip(),
    require=[p],
).requisite

svcwatch = [conf, wait_for_tmpfilesconf, collector_dir_maker, collectorwait]
svcrequire = [daemonreload, svcdisabled, Test("Collector directory created"), collectorwait_reload]

svcrunning = Service.running(
    "prometheus-node-exporter",
    watch=svcwatch,
    require=svcrequire,
    enable=True,
    require_in=Test("Before restarting collectors"),
).requisite
