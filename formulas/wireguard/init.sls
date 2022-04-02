#!objects

import os


from salt://lib/qubes.sls import fully_persistent_or_physical, fully_persistent, rw_only_or_physical, rw_only
from salt://lib/defs.sls import Perms


context = pillar("wireguard")



Cmd.wait(
    "reload systemd for wireguard",
    name="systemctl --system daemon-reload",
)


if fully_persistent_or_physical():
    with File.directory("/etc/systemd/system/wg-quick@.service.d"):
        File.managed(
            "/etc/systemd/system/wg-quick@.service.d/after-cloud.conf",
            contents="""[Unit]
After=cloud-init.service cloud-init-local.service
""",
            watch_in=[Cmd("reload systemd for wireguard")],
        )
        File.managed(
            "/etc/systemd/system/wg-quick@.service.d/restart.conf",
            contents="""[Service]
Restart=on-failure
RestartSec=15s
""",
            watch_in=[Cmd("reload systemd for wireguard")],
        )

    persreqs = [
        File("/etc/systemd/system/wg-quick@.service.d/after-cloud.conf"),
        File("/etc/systemd/system/wg-quick@.service.d/restart.conf"),
        Cmd("reload systemd for wireguard"),
    ]

    if not pillar("skip_package_installs"):
        Pkg.installed("wireguard-tools")
        persreqs.append(Pkg("wireguard-tools"))

else:
    persreqs = []



if rw_only_or_physical():
    File.directory(
        "/etc/wireguard",
        **Perms("root").owner_dir,
        require=persreqs,
        require_in=Qubes("wireguard"),
    )
    with Qubes.bind_dirs(
        "wireguard",
        directories=["/etc/wireguard"],
        require=persreqs,
    ):
        for network, netdata in context["networks"].items():
            File.managed(
                f"/etc/wireguard/{network}.conf",
                source="salt://wireguard/network.conf.j2",
                template="jinja",
                context=netdata,
                **Perms("root").owner_file,
                require=[File("/etc/wireguard")],
            )

with Qubes.enable_dom0_managed_service(
    "wg-quick@",
    qubes_service_name="wg-quick",
    enable=False,
):

    for network in context["networks"]:
        if fully_persistent:
            Service.enabled(
                f"wg-quick@{network}",
                require=persreqs,
            )
    
        if rw_only_or_physical():
            Service.running(
                f"wg-quick@{network} running",
                name=f"wg-quick@{network}",
                enable=True,
                watch=[File(f"/etc/wireguard/{network}.conf")] + persreqs,
                require=persreqs,
            )
