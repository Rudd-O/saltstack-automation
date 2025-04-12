#!objects

from shlex import quote
from copy import deepcopy


for network, netdata in pillar('wireguard:networks').items():
    for peer, peer_data in netdata["peers"].items():
        my_netdata = deepcopy(netdata)
        my_netdata["me"] = peer
        my_netdata["saveconfig"] = False
        fn = f"/tmp/wireguard/{network}/{peer}.conf"
        File.managed(
            fn,
            source="salt://wireguard/network.conf.j2",
            template="jinja",
            context=my_netdata,
            makedirs=True,
            show_changes=False,
        )
        qfn = quote(fn)
        Cmd.run(f"cat {qfn} ; qrencode -t ANSIUTF8 < {qfn}")
