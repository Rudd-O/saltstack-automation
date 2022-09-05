#!objects

from salt://lib/qubes.sls import updateable, template
from salt://lib/defs.sls import Perms
from salt://maint/config.sls import config
from salt://prometheus/exporter/node_exporter/config.sls import config as neconfig


def collector(n, ext=None):
    include(".".join(sls.split(".")[:-1]) + ".folder")
    colldir = Test("Collector directory created")
    textfile_directory = neconfig.paths.textfile_directory
    exe_path = neconfig.paths.collector_directory
    oldexe = f"/usr/local/bin/{n}"
    exe = f"{exe_path}/{n}"
    include(".".join(sls.split(".")[:-2]) + ".systemd")

    slsp = sls.replace(".", "/")
    n = sls.split(".")[-1]

    ext = ext if ext else ""

    File.absent(oldexe)

    if updateable():
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
            **Perms.dir,
        ).requisite

        service = File.managed(
            f'/etc/systemd/system/{n}.service',
            source=f"salt://{slsp}/{n}.service.j2",
            template="jinja",
            context={"textfile_directory": textfile_directory, "exe": exe},
            watch_in=[Cmd("Reload systemd for node exporter")],
            require=[prog, colldir],
            **Perms.file,
        ).requisite

        qubified = Qubes.enable_dom0_managed_service(
            f"{n} qubified",
            name=n,
            qubes_service_name="node_exporter",
            enable=False,
            require=[service],
        ).requisite

        timer = File.managed(
            f'/etc/systemd/system/{n}.timer',
            source=f"salt://{slsp}/{n}.timer",
            watch_in=[Cmd("Reload systemd for node exporter")],
            require=[qubified],
            **Perms.file,
        ).requisite

        enabled = Service.enabled(
            f"{n}.timer",
            require=[Cmd("Reload systemd for node exporter"), timer],
        ).requisite

        svcwatch = [prog, service, enabled]
        svcrequire = [timer]
    else:
        svcwatch = [colldir]
        svcrequire = []

    if not template():
        exec_ = Cmd.wait(
            f"systemctl --system start --no-block {n}",
            watch=svcwatch,
            require=svcrequire,
        ).requisite
