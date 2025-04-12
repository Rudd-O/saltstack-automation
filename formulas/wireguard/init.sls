#!objects

import os
import textwrap


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

se = Customselinux.policy_module_present(
    "wgping",
    contents=textwrap.dedent("""\
        module wgping 1.0;

        require {
            type ping_exec_t;
            type wireguard_t;
            type iptables_t;
            class file { getattr read open execute execute_no_trans map };
            class process { setcap noatsecure rlimitinh siginh };
            class icmp_socket { create setopt getopt recv_msg send_msg read write };
        }

        #============= wireguard_t ==============
        allow wireguard_t ping_exec_t:file { getattr read open execute execute_no_trans map };
        allow wireguard_t self:process { setcap };
        allow wireguard_t iptables_t:process { noatsecure rlimitinh siginh };
        allow wireguard_t self:icmp_socket { create setopt getopt recv_msg send_msg read write };
        """
    ),
    require=persreqs,
).requisite

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
            if network not in context["enabled"]: continue
            netdata["me"] = grains('id')
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
        if network not in context["enabled"]: continue
        if fully_persistent:
            Service.enabled(
                f"wg-quick@{network}",
                require=persreqs,
            )
    
        if rw_only_or_physical() and pillar("restart_services", True):
            Service.running(
                f"wg-quick@{network} running",
                name=f"wg-quick@{network}",
                enable=True,
                watch=[File(f"/etc/wireguard/{network}.conf")] + persreqs + [se],
                require=persreqs,
            )
