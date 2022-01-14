"""
Various states to help with deployment on Qubes VMs.
"""

import json
import os
import subprocess
from subprocess import check_output as co, CalledProcessError

try:
    from shlex import quote
except ImportError:
    from pipes import quote


def __virtual__():
    return "podman"


def _single(subname, *args, **kwargs):
    ret = __salt__["state.single"](*args, **kwargs)
    ret = list(ret.values())[0]
    ret["name"] = subname
    return ret


def present(name, image, options=None, enable=False):
    """
    Creates a container with a name.
    See https://www.qubes-os.org/doc/bind-dirs/ for more information.
    """
    options = options or []

    try:
        o = co(["podman", "container", "inspect", name])
        container_exists = True
        v = json.loads(o)
        try:
            existing_cmd = v[0]["Config"]["CreateCommand"]
        except (KeyError, IndexError):
            existing_cmd = []
    except CalledProcessError:
        existing_cmd = []
        container_exists = False

    cmd = ["podman", "run", "-d", "--name", name]
    for option in options:
        for key, value in option.items():
            key = "-" + key if len(key) < 2 else "--" + key
            cmd.extend([key, value])
    cmd += [image]

    rets = []
    a, success = rets.append, lambda: not rets or all(
        r["result"] != False for r in rets
    )

    if container_exists:
        if cmd != existing_cmd:
            for subcmd in "stop rm".split():
                if success():
                    a(
                        _single(
                            "Container %s" % subcmd,
                            "cmd.run",
                            name=" ".join(
                                quote(x) for x in ["podman", "container", subcmd, name]
                            ),
                        )
                    )
            if success():
                a(
                    _single(
                        "Container new start",
                        "cmd.run",
                        name=" ".join(quote(x) for x in cmd),
                    )
                )
        else:
            a(
                dict(
                    name="Container start",
                    result=True,
                    comment="Container %s already running with matching parameters"
                    % name,
                    changes={},
                )
            )
    else:
        if success():
            a(
                _single(
                    "Container start",
                    "cmd.run",
                    name=" ".join(quote(x) for x in cmd),
                )
            )

    if not __opts__["test"] and enable and success():
        unit, escaped_name = (
            co("podman generate systemd --no-header".split() + [name], text=True),
            co(["systemd-escape", name], text=True).rstrip(),
        )

        a(
            _single(
                "systemd service creation",
                "file.managed",
                name="/etc/systemd/system/container-%s.service" % escaped_name,
                contents=unit,
            )
        )

        if success():
            a(
                _single(
                    "systemd service enablement",
                    "service.enabled",
                    name="container-%s" % escaped_name,
                )
            )

    return dict(
        name=name,
        result=success(),
        comment="\n".join(r["comment"] for r in rets),
        changes=dict((r["name"], r["changes"]) for r in rets if r["changes"]),
    )


def _allocate_subx(type_, name, howmany):
    fn = "/etc/%s" % type_
    with open(fn, "r") as f:
        text = f.read()
        lines = text.splitlines()
        max = 100000
        adjusted = False
        for n, line in enumerate(lines):
            if line.startswith("#"):
                continue
            user, start, num = line.split(":")
            if user == name:
                lines[n] = "%s:%s:%s" % (user, start, howmany)
                adjusted = True
                break
            start = int(start)
            num = int(num)
            if start + num > max:
                max = start + num
        if not adjusted:
            lines.append("%s:%s:%s" % (name, max, howmany))
        text = "\n".join(lines) + "\n"
    ret = _single(fn, "file.managed", name=fn, contents=text)
    ret["name"] = name
    return ret


def allocate_subuid_range(name, howmany):
    return _allocate_subx("subuid", name, howmany)


def allocate_subgid_range(name, howmany):
    return _allocate_subx("subgid", name, howmany)
