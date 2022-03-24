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


def _escape_unit(name):
    if not name.endswith(".service"):
        name += ".service"
    return co(["systemd-escape", "-m", "--", name], text=True).rstrip()


def present(name, image, options=None, dryrun=False, enable=None):
    """
    Creates a container with a name, and runs it under systemd.

    If dryrun is specified, the existing properties of the
    container are checked, and changes are returned accordingly
    without making any changes.
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

    cmd = ["podman", "container", "create", "--name", name]
    for option in options:
        if hasattr(option, "items"):
            for key, value in option.items():
                key = "-" + key if len(key) < 2 else "--" + key
                cmd.extend([key + "=" + value])
        else:
            option = "-" + option if len(option) < 2 else "--" + option
            cmd.extend([option])
    cmd += [image]

    if dryrun:
        if not container_exists:
            return {
                "name": name,
                "comment": "Container %s would be created" % name,
                "changes": {"container create": name},
                "result": None if not __opts__["test"] else True,
            }
        if cmd != existing_cmd:
            return {
                "name": name,
                "comment": "Container %s would be recreated" % name,
                "changes": {"container recreate": name},
                "result": None if not __opts__["test"] else True,
            }
        return {
            "name": name,
            "comment": "Container %s needs no changes" % name,
            "changes": {},
            "result": True,
        }

    rets = []
    a, success = rets.append, lambda: not rets or all(
        r["result"] != False for r in rets
    )

    escaped_name = "container-" + _escape_unit(name)[:-8]
    unit_path = "/etc/systemd/system/%s.service" % escaped_name

    if container_exists:
        if cmd != existing_cmd:
            if os.path.exists(unit_path):
                a(
                    _single(
                        "Old systemd service stop",
                        "service.dead",
                        name=escaped_name,
                    )
                )

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
                        "Container new",
                        "cmd.run",
                        name=" ".join(quote(x) for x in cmd),
                    )
                )
        else:
            a(
                dict(
                    name="Container create",
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

    if success():
        if not __opts__["test"] or container_exists:

            unit = co("podman generate systemd --no-header".split() + [name], text=True)
            a(
                _single(
                    "systemd service creation",
                    "file.managed",
                    name=unit_path,
                    contents=unit,
                )
            )

        if success():
            if rets[-1]["changes"]:
                # Reload systemd because we changed the unit file.
                if not __opts__["test"]:
                    co(["systemctl", "--system", "daemon-reload"])
            a(
                _single(
                    "systemd service enablement",
                    "service.running",
                    enable=enable,
                    name=escaped_name,
                )
            )

    return dict(
        name=name,
        result=success(),
        comment="\n".join(r["comment"] for r in rets),
        changes=dict((r["name"], r["changes"]) for r in rets if r["changes"]),
    )


def _absent_or_dead(name, mode):
    """
    Stops a container by name.
    """
    try:
        o = co(["podman", "container", "inspect", name])
        container_exists = True
        v = json.loads(o)
        is_running = v[0]["State"]["Running"]
    except CalledProcessError:
        container_exists = False
        is_running = False

    rets = []
    a, success = rets.append, lambda: not rets or all(
        r["result"] != False for r in rets
    )

    escaped_name = "container-" + _escape_unit(name)[:-8]
    unit_path = "/etc/systemd/system/%s.service" % escaped_name

    if container_exists:
        if os.path.exists(unit_path):
            a(
                _single(
                    "Old systemd service stop",
                    "service.dead",
                    name=escaped_name,
                )
            )

            if success() and mode == "absent":
                a(
                    _single(
                        "systemd service deletion",
                        "file.absent",
                        name=unit_path,
                    )
                )
                if success() and rets[-1]["changes"]:
                    # Reload systemd because we deleted the unit file.
                    if not __opts__["test"]:
                        co(["systemctl", "--system", "daemon-reload"])

        subcmds = ["stop"] if is_running else []
        if mode == "absent":
            subcmds.append("rm")
        for subcmd in subcmds:
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

    return dict(
        name=name,
        result=success(),
        comment="\n".join(r["comment"] for r in rets),
        changes=dict((r["name"], r["changes"]) for r in rets if r["changes"]),
    )


def dead(name):
    """
    Stops a container by name.
    """
    return _absent_or_dead(name, mode="dead")


def absent(name):
    """
    Stops and removes a container by name.
    """
    return _absent_or_dead(name, mode="absent")


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
