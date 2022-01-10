from __future__ import print_function

import collections
import re
import shlex


def quote(s):
    """iptables.rules quoting rules."""
    if '"' in s or " " in s:
        return '"' + s.replace('"', '\\"') + '"'
    return s


def unique(l):
    x = collections.OrderedDict()
    for n in l:
        x[n] = True
    return list(x.keys())


def resolve_nodegroup(host_or_network, nodegroups):
    path = host_or_network.split(":")
    while path:
        nodegroups = nodegroups[path[0]]
        path = path[1:]
    assert isinstance(nodegroups, list), (host_or_network, nodegroups)
    return nodegroups


def parse_ip_and_or_mask(s):
    try:
        addr, mask = s.split("/", 1)
    except Exception:
        addr, mask = s, "32"
    try:
        first, second, third, fourth = addr.split(".", 3)
    except Exception:
        raise KeyError(s)
    for octet in [first, second, third, fourth]:
        try:
            octet = int(octet)
        except ValueError:
            raise KeyError(s)
        if octet < 0 or octet > 255:
            raise KeyError(s)
    try:
        mask = int(mask)
    except ValueError:
        raise KeyError(s)
    if mask < 0 or mask > 32:
        raise KeyError(s)
    return s


def resolve(host_or_network, homenetwork, nodegroups):
    if isinstance(host_or_network, list):
        addrs = []
        for x in host_or_network:
            addrs.extend(resolve(x, homenetwork, nodegroups))
        addrs, (host_or_network, addrs)
        return addrs
    if host_or_network == "me":
        addrs = []
        for addrgrp in __salt__["grains.get"]("ip4_interfaces").values():
            for addr in addrgrp:
                if addr == "127.0.0.1":
                    continue
                addrs.append(addr)
        return addrs
    if host_or_network.startswith("N@"):
        addrs = []
        for x in resolve_nodegroup(host_or_network[2:], nodegroups):
            addrs.extend(resolve(x, homenetwork, nodegroups))
        addrs, (host_or_network, addrs)
        return addrs
    try:
        return [parse_ip_and_or_mask(host_or_network)]
    except KeyError:
        pass
    try:
        return [homenetwork["networks"][host_or_network]]
    except KeyError:
        pass
    try:
        return [homenetwork["physical_hosts"][host_or_network]]
    except KeyError:
        pass
    try:
        return [homenetwork["vms"][host_or_network]]
    except KeyError:
        pass
    try:
        return [homenetwork["unsalted"][host_or_network]["ip"]]
    except KeyError:
        pass
    addrs = []
    for iface, ifacedata in homenetwork["zips"][host_or_network].items():
        addrs.append(ifacedata["addr"])
    assert addrs, (host_or_network, addrs)
    return addrs


def _inherit_tree(rule):
    for subrule in rule.get("rules", []):
        for k, v in list(rule.items()):
            if k == "rules":
                continue
            if k not in subrule:
                subrule[k] = v
        _inherit_tree(subrule)
    if "rules" in rule:
        for k in list(rule.keys()):
            if k != "rules":
                del rule[k]
    return rule


def _rule_to_iptables(
    group_name,
    rule,
    homenetwork,
    nodegroups,
    default_chain=None,
):
    parts = []
    protos = []
    srcs = []
    dests = []

    ignore = set()
    child_rules = []
    seen_action = False

    for k, v in list(rule.items()):
        if k == "rules":
            for rule in v:
                child_rules.extend(
                    rule_to_iptables(
                        group_name,
                        rule,
                        homenetwork,
                        nodegroups,
                        default_chain,
                    )
                )
            break
        if k == "raw":
            parts.extend(shlex.split(v))
            seen_action = True
        elif k == "proto":
            if not isinstance(v, list):
                v = [v]
            for x in v:
                protos.append(["-p", x])
        elif k == "to_ports":
            if not rule.get("proto") and not protos:
                protos = [["-p", "tcp"], ["-p", "udp"]]
            if isinstance(v, str) and ("," in v or ":" in v):
                parts.extend(
                    [
                        "-m",
                        "multiport",
                        "--dports",
                        ",".join([x.strip() for x in v.split(",") if x.strip()]),
                    ]
                )
            elif (isinstance(v, str) and re.match("[0-9]+", v)) or isinstance(v, int):
                parts.extend(["--dport", v])
            else:
                assert 0, "invalid to_ports %s" % v
        elif k == "pkttype":
            parts.extend(["-m", "pkttype", "--pkt-type", v])
            del child_must_process[k]
        elif k == "action":
            assert not seen_action, (rule, seen_action)
            assert v.upper() in [
                "ACCEPT",
                "REJECT",
                "DROP",
                "RETURN",
                "TEE",
                "LOG",
                "DNAT",
                "MASQUERADE",
            ], rule
            if v.upper() == "TEE":
                assert rule.get("gateway"), (rule, "has no gateway")
                gateway = resolve(rule["gateway"], homenetwork, nodegroups)
                if len(gateway) != 1:
                    assert 0, (
                        "rule",
                        rule,
                        "gateway",
                        rule["gateway"],
                        "resolves to more than one address",
                    )
                gateway = gateway[0]
                parts.extend(["-j", v.upper(), "--gateway", gateway])
                ignore.add("gateway")
            elif v.upper() == "DNAT":
                assert rule.get("chain", default_chain) == "PREROUTING", (
                    "rule",
                    rule,
                    "does not go to the PREROUTING chain",
                )
                assert rule.get("dnat-to"), (rule, "has no dnat-to")
                dnat_to = rule["dnat-to"]
                if not isinstance(dnat_to, list):
                    dnat_to = [dnat_to]
                try:
                    dnat_to, dnat_ports = [s.split(":", 1)[0] for s in dnat_to], [
                        s.split(":", 1)[1] for s in dnat_to
                    ]
                    dnat_port = dnat_ports[0]
                except IndexError:
                    dnat_port = None
                dnat_to = resolve(dnat_to, homenetwork, nodegroups)
                if len(dnat_to) > 1:
                    assert 0, (
                        "rule",
                        rule,
                        "dnat-to",
                        rule["dnat-to"],
                        "resolves to more than one address",
                    )
                dnat_to = dnat_to[0]
                if dnat_port:
                    dnat_to = dnat_to + ":" + dnat_port
                parts.extend(["-j", v.upper(), "--to-destination", dnat_to])
                ignore.add("dnat-to")
            elif v.upper() == "MASQUERADE":
                assert rule.get("chain", default_chain) == "POSTROUTING", (
                    "rule",
                    rule,
                    "does not go to the POSTROUTING chain",
                )
                parts.extend(["-j", v.upper()])
            elif v.upper() == "LOG":
                parts.extend(["-j", v.upper()])
                if "prefix" in rule:
                    parts.extend(["--log-prefix", rule["prefix"]])
                    ignore.add("prefix")
            else:
                parts.extend(["-j", v.upper()])
            seen_action = v
        elif k == "from":
            vv = resolve(v, homenetwork, nodegroups)
            for vvv in vv:
                srcs.append(["-s", vvv])
        elif k == "to":
            vv = resolve(v, homenetwork, nodegroups)
            for vvv in vv:
                dests.append(["-d", vvv])
        elif k == "comment":
            # processed somewhere else
            pass
        elif k == "chain":
            default_chain = v
        elif k not in ignore:
            assert 0, (group_name, k, v, "unknown stanza %s" % k)

    if child_rules:
        return child_rules

    srcs = srcs or [[]]
    dests = dests or [[]]
    protos = protos or [[]]
    assert seen_action, ("rule", rule, "has no action")

    rules = []
    if seen_action:
        for src in srcs:
            for dest in dests:
                for proto in protos:
                    rules.append(
                        [default_chain]
                        + proto
                        + src
                        + dest
                        + parts
                        + [
                            "-m",
                            "comment",
                            "--comment",
                            group_name
                            + (": " + rule["comment"] if "comment" in rule else ""),
                        ]
                    )
    for n, rule in enumerate(rules[:]):
        rules[n] = " ".join(quote(str(x)) for x in rule)
    return unique(rules)


def rule_to_iptables(
    group_name,
    rule,
    homenetwork,
    nodegroups,
    default_chain=None,
):
    rule = _inherit_tree(rule)
    return _rule_to_iptables(group_name, rule, homenetwork, nodegroups, default_chain)
