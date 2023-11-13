#!objects

import os
from shlex import quote


from salt://lib/qubes.sls import fully_persistent_or_physical, fully_persistent, rw_only_or_physical, rw_only
from salt://lib/defs.sls import Perms, as_plain_dict
from salt://openvpn/config.sls import config


Cmd.wait(
    "reload systemd for openvpn",
    name="systemctl --system daemon-reload",
)


if fully_persistent_or_physical():
    if pillar("skip_package_installs"):
        pkg = Test.nop("OpenVPN install").requisite
    else:
        pkg = Pkg.installed("openvpn", pkgs=["openssl", "openvpn"]).requisite

    en1 = Qubes.enable_dom0_managed_service(
        "openvpn-client@",
        qubes_service_name="openvpn-client",
        enable=False,
        require=[pkg],
    ).requisite
    en2 = Qubes.enable_dom0_managed_service(
        "openvpn-server@",
        qubes_service_name="openvpn-server",
        enable=False,
        require=[pkg],
    ).requisite

    persreqs = []

    for server in config.servers:
        persreqs.append(
            Service.enabled(
                f"openvpn-server@{server}",
                require=[en1, en2],
            ).requisite
        )

else:
    persreqs = []


if rw_only_or_physical():
    bind = Qubes.bind_dirs(
        "openvpn",
        directories=["/etc/openvpn", "/var/lib/openvpn"],
        require=persreqs,
    ).requisite

    for server, data in config.servers.items():
        data["server"] = server
        
        f = File.managed(
            f"/etc/openvpn/server/{server}.conf",
            source="salt://openvpn/servers/server.conf.j2",
            template="jinja",
            context=data,
            user="root",
            group="openvpn",
            mode="0640",
            require=[bind],
        ).requisite

        dpath = f"/etc/openvpn/server/{server}"
        d = File.directory(
            dpath,
            user="root",
            group="openvpn",
            mode="0750",
            require=[f],
        ).requisite
        ca = File.managed(
            f"{dpath}/ca.crt",
            contents=data.ca_certificate,
            require=[d],
        ).requisite
        crt = File.managed(
            f"{dpath}/server.crt",
            contents=data.server_certificate,
            require=[d],
        ).requisite
        key = File.managed(
            f"{dpath}/server.key",
            contents=data.server_private_key,
            require=[d],
        ).requisite

        dhpath = f"{dpath}/dh.pem"
        c = Cmd.run(
            "openssl dhparam -out %s %s" % (
                quote(dhpath),
                quote(str(data.server_key_bits)),
            ),
            creates=dhpath,
            require=[d],
        ).requisite

        s = Service.running(
            f"openvpn-server@{server} running",
            name=f"openvpn-server@{server}",
            watch=[f, ca, crt, key, c] + persreqs,
        ).requisite
        persreqs.append(s)

        ccdpath = f"/etc/openvpn/server/{server}/ccd"
        ccd = File.directory(
            ccdpath,
            require=[d],
        ).requisite

        for client, client_data in data.clients.items():
            if client_data.get("remove"):
                File.absent(f"{ccdpath}/{client}", require_in=[s])
            else:
                File.managed(
                    f"{ccdpath}/{client}",
                    require=[ccd],
                    contents="""
ifconfig-push {{ ip }} 255.255.255.255
push "route vpn_gateway 255.255.255.255 {{ ip }} 0"
{%- for client_route in client_routes %}
push "route {{ client_route }} {{ ip }} 0"
{%- endfor %}
    """.strip(),
                    require_in=[s],
                    template="jinja",
                    context={
                        "ip": client_data.ip,
                        "local_ip": data.local_ip,
                        "client_routes": data.client_routes,
                    }
                )

Test.nop("OpenVPN setup finished", require=persreqs)