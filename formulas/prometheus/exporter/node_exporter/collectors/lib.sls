#!objects

from salt://lib/qubes.sls import updateable, template
from salt://lib/defs.sls import Perms, ReloadSystemdOnchanges
from salt://maint/config.sls import config
from salt://prometheus/exporter/node_exporter/config.sls import config as neconfig

def collector(n, ext=None):
    reloadsystemd = ReloadSystemdOnchanges("collector " + n)

    include(".".join(sls.split(".")[:-1]) + ".folder")
    colldir = Test("Collector directory created")
    exe_path = neconfig.paths.collector_directory
    oldexe = f"/usr/local/bin/{n}"
    exe = f"{exe_path}/{n}"

    slsp = sls.replace(".", "/")
    n = sls.split(".")[-1]

    ext = ext if ext else ""

    File.absent(oldexe)

    selinux_state = __salt__["file.file_exists"]("/usr/sbin/semanage") and __salt__["selinux.getenforce"]()
    selinux = {
        "seuser": "system_u",
        "serole": "object_r",
        "setype": "bin_t",
        "serange": "s0",
    } if selinux_state in ("Permissive", "Enforcing") else None
    selinux = None
    prog = File.managed(
        exe,
        source=f"salt://{slsp}/{n}{ext}",
        template="jinja" if ext else None,
        context={
            "exclude_services": [".+[.]scope$"],
            "exclude_paths": config['update'].restart_exclude_paths,
        },
        makedirs=True,
        require=[Test("Collector directory created")],
        selinux=selinux,
        **Perms.dir,

    ).requisite

    service = File.managed(
        f'/etc/systemd/system/{n}.service',
        source=f"salt://{slsp}/{n}.service.j2",
        template="jinja",
        context={"exe": exe},
        onchanges_in=[reloadsystemd],
        require=[prog, colldir],
        **Perms.file,
    ).requisite

    nonqubified = Qubes.disable_dom0_managed_service(
        f"{n} disqubified",
        name=n,
        disable=False,
        onchanges_in=[reloadsystemd],
    ).requisite
    nonqubified_timer = Qubes.disable_dom0_managed_service(
        f"{n} timer disqubified",
        name=f"{n}.timer",
        qubes_service_name="node_exporter",
        onchanges_in=[reloadsystemd],
        require=[service, nonqubified],
    ).requisite

    timer = File.managed(
        f'/etc/systemd/system/{n}.timer',
        source=f"salt://{slsp}/{n}.timer",
        onchanges_in=[reloadsystemd],
        require=[nonqubified_timer],
        **Perms.file,
    ).requisite

    enabled = Service.enabled(
        f"{n}.timer",
        qubes_service_name="node_exporter",
        require=[reloadsystemd, timer],
    ).requisite

    svcwatch = [prog, service, enabled]
    svcrequire = [timer, reloadsystemd]

    exec_ = Cmd.wait(
        f"systemctl --system restart --no-block {n}",
        watch=svcwatch,
        require=svcrequire,
    ).requisite
