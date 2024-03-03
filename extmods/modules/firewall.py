import collections
import itertools
import pprint
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


def grp(lst):
    if hasattr(lst, "append"):
        if len(lst) > 1:
            return "{ " + ", ".join(lst) + " }"
        else:
            return lst[0]
    return lst


def resolve_nodegroup(host_or_network, nodegroups):
    path = host_or_network.split(":")
    original_path = path[:]
    while path:
        try:
            nodegroups = nodegroups[path[0]]
        except KeyError:
            raise KeyError("no such nodegroup %s" % path[0])
        path = path[1:]
    assert isinstance(nodegroups, list), f"resolve_nodegroup: path {original_path} did not result in a list, it resulted in {nodegroups}"
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
    if host_or_network in ("me", "self@"):
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
    try:
        addrs = []
        for iface, ifacedata in homenetwork["zips"][host_or_network].items():
            addrs.append(ifacedata["addr"])
        assert addrs, (host_or_network, addrs)
        return addrs
    except KeyError:
        pass
    addrs = __salt__["dnsutil.A"](host_or_network)
    assert addrs, (host_or_network, addrs)
    return addrs


def _transform_simple_rule_to_iptables(
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
    seen_action = False

    for k, v in list(rule.items()):
        if k == "raw":
            parts.extend(shlex.split(v))
            seen_action = True
        elif k == "proto":
            if not isinstance(v, list):
                v = [v]
            for x in v:
                protos.append(["-p", x])
        elif k in ("to_ports", "from_ports"):
            pflags = "--dports" if k == "to_ports" else "--sports"
            pflag = "--dport" if k == "to_ports" else "--sport"
            if not rule.get("proto") and not protos:
                protos = [["-p", "tcp"], ["-p", "udp"]]
            if isinstance(v, str) and ("," in v or ":" in v):
                parts.extend(
                    [
                        "-m",
                        "multiport",
                        pflags,
                        ",".join(x.strip() for x in v.split(",") if x.strip()),
                    ]
                )
            elif isinstance(v, list):
                for x in v:
                    if not isinstance(x, int):
                        assert 0, "Port %r is not an integer" % x
                parts.extend(
                    [
                        "-m",
                        "multiport",
                        pflags,
                        ",".join(str(x) for x in v),
                    ]
                )
            elif (isinstance(v, str) and re.match("[0-9]+", v)) or isinstance(v, int):
                parts.extend([pflag, v])
            else:
                assert 0, "invalid %s %s" % (k, v)
        elif k == "pkttype":
            parts.extend(["-m", "pkttype", "--pkt-type", v])
        elif k == "icmp_type":
            parts.extend(["--icmp-type", v])
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
                assert rule.get("target"), (rule, "has no target")
                dnat_to = rule["target"]
                if not isinstance(dnat_to, dict):
                    assert 0, f"{dnat_to} is not a dictionary with address and port members"
                dnat_to, dnat_port = resolve(dnat_to["address"], homenetwork, nodegroups), dnat_to.get("port")
                if len(dnat_to) > 1:
                    assert 0, (
                        "rule",
                        rule,
                        "target",
                        rule["target"],
                        "resolves to more than one address",
                    )
                dnat_to = dnat_to[0]
                if dnat_port:
                    dnat_to = dnat_to + ":" + dnat_port
                parts.extend(["-j", v.upper(), "--to-destination", dnat_to])
                ignore.add("target")
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
        elif k == "input_interface":
            if isinstance(v, str):
                v = [v]
            for vvv in v:
                srcs.append(["-i", vvv])
        elif k == "output_interface":
            if isinstance(v, str):
                v = [v]
            for vvv in v:
                dests.append(["-o", vvv])
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
            assert 0, (k, v, "unknown stanza %s" % k)

    srcs = srcs or [[]]
    dests = dests or [[]]
    protos = protos or [[]]
    assert seen_action, ("rule", rule, "has no action")

    rules = []
    for src in srcs:
        for dest in dests:
            for proto in protos:
                rules.append(
                    [default_chain]
                    + proto
                    + src
                    + dest
                    + parts
                    + ([
                           "-m",
                           "comment",
                           "--comment",
                           rule["comment"],
                       ] if "comment" in rule else [])
                )
    for n, rule in enumerate(rules[:]):
        rules[n] = " ".join(quote(str(x)) for x in rule)
    return unique(rules)



def _transform_simple_rule_to_nftables(
    rule,
    homenetwork,
    nodegroups,
    ip_version="ip",
):
    parts = []
    protos = []
    srcs = []
    dests = []
    action = None

    def no_nft(k):
        assert 0, f"nftables not supported for {k}"

    ignore = set()

    for k, v in list(rule.items()):
        negation = False
        if k.startswith("not_"):
            k = k[4:]
            negation = True

        if k == "raw":
            assert not negation, f"negation not allowed for {k}"
            parts.extend([v])
            action = "raw"
        elif k == "proto":
            assert not negation, f"negation not allowed for {k}"
            if not isinstance(v, list):
                v = [v]
            for x in v:
                protos.append(x)
        elif k in ("to_ports", "from_ports"):
            assert not negation, f"negation not allowed for {k}"
            flag = "dport" if k == "to_ports" else "sport"
            if not rule.get("proto") and not protos:
                protos = ["tcp", "udp"]
            if isinstance(v, str) and ("," in v or ":" in v):
                parts.extend([
                    flag,
                    grp([x.strip().replace(":", "-") for x in v.split(",") if x.strip()])
                ])
            elif isinstance(v, list):
                for x in v:
                    if not isinstance(x, int):
                        assert 0, "Port %r is not an integer" % x
                parts.extend([
                    flag,
                    grp([str(x).replace(":", "-") for x in v])
                ])
            elif (isinstance(v, str) and re.match("^[0-9]+$", v)) or isinstance(v, int):
                parts.extend([flag, str(v).replace(":", "-")])
            else:
                assert 0, "invalid %s %s" % (k, v)
        elif k == "pkttype":
            assert not negation, f"negation not allowed for {k}"
            parts.extend(["meta", "pkttype", v])
        elif k == "icmp_type":
            assert not negation, f"negation not allowed for {k}"
            if protos:
                if protos != ["icmp"]:
                    assert 0, f"cannot use icmp_type with protos {protos}"
            else:
                protos = ["icmp"]
            parts.extend(["icmp", "type", v])
        elif k == "action":
            assert not negation, f"negation not allowed for {k}"
            assert not action, f"rule {rule} already has action {action}"
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
                no_nft(v)
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
                assert rule.get("target"), (rule, "has no target")
                dnat_to = rule["target"]
                if not isinstance(dnat_to, dict):
                    assert 0, f"{dnat_to} is not a dictionary with address and port members"
                dnat_to, dnat_port = resolve(dnat_to["address"], homenetwork, nodegroups), dnat_to.get("port")
                if len(dnat_to) > 1:
                    assert 0, (
                        "rule",
                        rule,
                        "target",
                        rule["target"],
                        "resolves to more than one address",
                    )
                dnat_to = dnat_to[0]
                if dnat_port:
                    dnat_to = dnat_to + ":" + dnat_port
                    assert 0, f"dnat ports {dnat_to} are not yet supported"
                ignore.add("target")
                action = " ".join(["dnat", "to", dnat_to])
            elif v.upper() == "MASQUERADE":
                action = v.lower()
            elif v.upper() == "LOG":
                no_nft(v)
                parts.extend(["-j", v.upper()])
                if "prefix" in rule:
                    parts.extend(["--log-prefix", rule["prefix"]])
                    ignore.add("prefix")
            else:
                action = v.lower()
        elif k == "input_interface":
            assert not negation, f"negation not allowed for {k}"
            if isinstance(v, str):
                v = [v]
            srcs.append(["iifname", grp(v)])
        elif k == "output_interface":
            assert not negation, f"negation not allowed for {k}"
            if isinstance(v, str):
                v = [v]
            srcs.append(["oifname", grp(v)])
        elif k == "from":
            vv = resolve(v, homenetwork, nodegroups)
            srcs.append([ip_version, "saddr"] + (["!="] if negation else []) + [grp(vv)])
        elif k == "to":
            vv = resolve(v, homenetwork, nodegroups)
            dests.append([ip_version, "daddr"] + (["!="] if negation else []) + [grp(vv)])
        elif k == "comment":
            assert not negation, f"negation not allowed for {k}"
            # processed somewhere else
            pass
        elif k == "chain":
            no_nft(k)
        elif k not in ignore:
            assert 0, (k, v, "unknown stanza %s" % k)

    srcs = srcs or [[]]
    dests = dests or [[]]
    protos = protos or [None]
    assert action, ("rule", rule, "has no action")
    if action == "raw":
        action = ""

    rules = []
    for src in srcs:
        for dest in dests:
            for proto in protos:
                thisparts = list(parts)
                for x, part in enumerate(thisparts):
                    if part == "dport" or part == "sport":
                        thisparts = thisparts[:x] + [proto] + thisparts[x:]
                        break            
                rules.append(
                    ([] if not proto else [ip_version, "protocol", proto])
                    + src
                    + dest
                    + thisparts
                    + (
                        [action] if action else []
                    ) + (
                        [
                            f"# {rule['comment']}"
                        ]
                        if "comment" in rule else []
                    )
                )
    for n, rule in enumerate(rules[:]):
        rules[n] = " ".join(str(x) for x in rule)
    return unique(rules)


def complex_rule_to_simple_rules(
    rule,
    homenetwork,
    nodegroups,
    default_chain=None,
    level=0,
):
    def add(adict, origin, k, v):
        if k == "comment" and "comment" in adict:
            v = "%s: %s" % (adict["comment"], v)
        else:
            assert k not in adict, f"stanza {k} in {pprint.pformat(origin)} would overwrite a preexisting value in {pprint.pformat(adict)}"
        adict[k] = v

    if isinstance(rule, dict):
        children = [collections.OrderedDict()]
        for k1, v1 in rule.items():
            if k1 in ("combine", "rules"):
                if k1 == "rules":
                    combine = [rule[k1]]
                else:
                    combine = rule[k1]
                combined_tuples = [
                    x for x in itertools.product(*combine)
                ]
                new_rules = []
                for tupl in combined_tuples:
                    newrule = {}
                    for inner_dict in tupl:
                        try:
                            for k, v in inner_dict.items():
                                add(newrule, inner_dict, k, v)
                        except Exception:
                            assert 0, inner_dict
                    new_rules.append(newrule)
                child_stanzas_list = []
                for new_rule in new_rules:
                    child_stanzas_list.extend(complex_rule_to_simple_rules(new_rule, homenetwork, nodegroups, default_chain, level+1))
                new_children = []
                for child in children:
                    for child_stanzas in child_stanzas_list:
                        new_child = collections.OrderedDict(child)
                        for k, v in child_stanzas.items():
                            add(new_child, child_stanzas, k, v)
                        new_children.append(new_child)
                children = new_children
            else:
                for a in children:
                    add(a, rule, k1, v1)

    else:
        assert 0, (type(rule), rule)
    return children


def rule_to_iptables(
    rule,
    homenetwork,
    nodegroups,
    default_chain=None,
):
    try:
        res = complex_rule_to_simple_rules(rule, homenetwork, nodegroups, default_chain)
        res = [x for r in res for x in _transform_simple_rule_to_iptables(r, homenetwork, nodegroups, default_chain)]
        return res
    except (AssertionError, KeyError) as exc:
        raise Exception("Cannot process iptables rule %s: %s" % (rule, exc)) from exc


def rule_to_nftables(
    rule,
    homenetwork,
    nodegroups,
    ip_version,
):
    try:
        res = complex_rule_to_simple_rules(rule, homenetwork, nodegroups)
        res = [x for r in res for x in _transform_simple_rule_to_nftables(r, homenetwork, nodegroups, ip_version=ip_version)]
        return res
    except (AssertionError, KeyError) as exc:
        raise Exception("Cannot process nftables rule %s: %s" % (rule, exc)) from exc


def ruleset_to_iptables(
    ruleset,
    homenetwork,
    nodegroups,
    default_chain=None,
):
    if isinstance(ruleset, dict):
        r = []
        for k, v in ruleset.items():
            for v2 in v:
                if "comment" in v2:
                    v2["comment"] = "%s: %s" % (k, v2["comment"])
                else:
                    v3 = collections.OrderedDict()
                    v3["comment"] = k
                    try:
                        v3.update(v2)
                    except ValueError as e:
                        raise ValueError(f"rule {pprint.pformat(v2)} is not well-formed ({e})" )
                    v2 = v3
                r.append(v2)
        ruleset = r
    rules = []
    for rulegroup in ruleset:
        for rule in rule_to_iptables(rulegroup, homenetwork, nodegroups, default_chain):
            rules.append(rule)
    return rules


def ruleset_to_nftables(
    ruleset,
    homenetwork,
    nodegroups,
    ip_version,
):
    if isinstance(ruleset, dict):
        r = []
        for k, v in ruleset.items():
            for v2 in v:
                if "comment" in v2:
                    v2["comment"] = "%s: %s" % (k, v2["comment"])
                else:
                    v3 = collections.OrderedDict()
                    v3["comment"] = k
                    try:
                        v3.update(v2)
                    except ValueError as e:
                        raise ValueError(f"rule {pprint.pformat(v2)} is not well-formed ({e})" )
                    v2 = v3
                r.append(v2)
        ruleset = r
    rules = []
    for rulegroup in ruleset:
        for rule in rule_to_nftables(rulegroup, homenetwork, nodegroups, ip_version):
            rules.append(rule)
    return rules
