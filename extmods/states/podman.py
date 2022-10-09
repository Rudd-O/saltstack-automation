"""
Various states to help with deployment on Qubes VMs.
"""

import json
import os
import re
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

def _make_container_command(options, pod_name=None):
    cmd = ["podman", "container", "create"]
    if pod_name is not None:
        cmd.extend(["--pod", pod_name])
    image = None
    for option in options:
        if hasattr(option, "items"):
            for key, value in option.items():
                if key == "image":
                    image = value
                    continue
                key = "-" + key if len(key) < 2 else "--" + key
                cmd.extend([key + "=" + value])
        else:
            option = "-" + option if len(option) < 2 else "--" + option
            cmd.extend([option])
    assert image is not None, ("container with no image", pod_name, options)
    cmd += [image]
    return cmd


def _make_pod_command(pod_name, options):
    cmd = ["podman", "pod", "create"]
    for option in options:
        if hasattr(option, "items"):
            for key, value in option.items():
                key = "-" + key if len(key) < 2 else "--" + key
                cmd.extend([key + "=" + value])
        else:
            option = "-" + option if len(option) < 2 else "--" + option
            cmd.extend([option])
    cmd += [pod_name]
    return cmd



def pod_running(name, options, containers, dryrun=False, enable=None):
    """
    Creates a pod with a list of containers under it,
    then runs it with systemd.

    If dryrun is specified, the existing properties of the
    container are checked, and changes are returned accordingly
    without making any changes.
    """
    options = options or []
    cmd = _make_pod_command(name, options)
    container_cmds = [
        _make_container_command(c, pod_name=name)
        for c in containers
    ]

    try:
        o = co(["podman", "pod", "inspect", name])
        pod_exists = True
        v = json.loads(o)
        existing_cmd = v["CreateCommand"]
    except CalledProcessError:
        pod_exists = False
        existing_cmd = []
        existing_container_cmds = []

    if existing_cmd:
        existing_containers = [x["Name"] for x in v.get("Containers", [])]
        existing_container_cmds = []
        for existing_container in existing_containers:
            o = co(["podman", "container", "inspect", existing_container])
            v = json.loads(o)
            existing_container_cmds.append(v[0]["Config"]["CreateCommand"])

    existing_container_cmds_equal = True
    if len(container_cmds) + 1 != len(existing_container_cmds):
        # mismatched expected vs. real number
        existing_container_cmds_equal = False

    if existing_container_cmds_equal:
        ee = []
        for ccmd in container_cmds:
            for ecmd in existing_container_cmds:
                if ccmd == ecmd:
                    ee.append(True)
                    break
        if len(ee) != len(container_cmds):
            existing_container_cmds_equal = False

    if dryrun:
        if not pod_exists:
            return {
                "name": name,
                "comment": "Pod %s would be created" % name,
                "changes": {"pod create": cmd, "containers create": container_cmds},
                "result": None if not __opts__["test"] else True,
            }
        if cmd != existing_cmd:
            return {
                "name": name,
                "comment": "Pod %s would be recreated" % name,
                "changes": {"pod recreate": cmd, "containers recreate": container_cmds},
                "result": None if not __opts__["test"] else True,
            }
        if not existing_container_cmds_equal:
            return {
                "name": name,
                "comment": "Pod %s's containers would be recreated" % name,
                "changes": {"containers recreate": container_cmds},
                "result": None if not __opts__["test"] else True,
            }

        return {
            "name": name,
            "comment": "Pod %s needs no changes" % name,
            "changes": {},
            "result": True,
        }

    rets = []
    a, success = rets.append, lambda: not rets or all(
        r["result"] != False for r in rets
    )

    escaped_name = "pod-" + _escape_unit(name)[:-8]
    unit_path = "/etc/systemd/system/%s.service" % escaped_name

    def create():
        if success():
            a(
                _single(
                    "Pod create",
                    "cmd.run",
                    name=" ".join(quote(x) for x in cmd),
                )
            )
        for ccmd in container_cmds:
            if success():
                a(
                    _single(
                        "Container create",
                        "cmd.run",
                        name=" ".join(quote(x) for x in ccmd),
                    )
                )   

    if pod_exists:
        if cmd != existing_cmd or not existing_container_cmds_equal:
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
                            "Pod %s" % subcmd,
                            "cmd.run",
                            name=" ".join(
                                quote(x) for x in ["podman", "pod", subcmd, name]
                            ),
                        )
                    )
            create()
        else:
            a(
                dict(
                    name="Pod create",
                    result=True,
                    comment="Pod %s already running with matching parameters"
                    % name,
                    changes={},
                )
            )
    else:
        create()

    if success():
        if not __opts__["test"] or pod_exists:

            unit = co("podman generate systemd -n --no-header".split() + [name], text=True)
            allunits = unit.split("[Unit]")
            unit = [a for a in allunits if "Description=Podman pod" in a][0]
            unit = "[Unit]\n" + unit
            unitls = unit.splitlines(True)
            execstartline = [n for n, l in enumerate(unitls) if l.startswith("ExecStart=")][0]
            execstopline = [n for n, l in enumerate(unitls) if l.startswith("ExecStop=")][0]
            execstoppostline = [n for n, l in enumerate(unitls) if l.startswith("ExecStopPost=")][0]
            unitls[execstartline] = unitls[execstartline].split("start")[0] + " pod start " + name + "\n"
            unitls[execstopline] = unitls[execstopline].split("stop")[0] + " pod stop " + name + "\n"
            unitls[execstoppostline] = unitls[execstoppostline].split("stop")[0] + " pod stop -i " + name + "\n"
            unit = "".join([
                u for u in unitls
                if not u.startswith("Requires=container")
                and not u.startswith("BindsTo=container")
                and not u.startswith("Before=container") 
                and not u.startswith("After=container")
                and not u.startswith("#")
            ])
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


def _absent_or_dead(name, mode, container_or_pod="container"):
    """
    Stops a container by name.
    """
    try:
        o = co(["podman", container_or_pod, "inspect", name])
        container_exists = True
        v = json.loads(o)
        if container_or_pod == "container":
            is_running = v[0]["State"]["Running"]
        else:
            is_running = v["State"] == "Running"
    except CalledProcessError:
        container_exists = False
        is_running = False

    rets = []
    a, success = rets.append, lambda: not rets or all(
        r["result"] != False for r in rets
    )

    escaped_name = container_or_pod + "-" + _escape_unit(name)[:-8]
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
                        "%s %s" % (container_or_pod.capitalize(), subcmd),
                        "cmd.run",
                        name=" ".join(
                            quote(x) for x in ["podman", container_or_pod, subcmd, name]
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


def pod_dead(name):
    """
    Stops a pod by name.
    """
    return _absent_or_dead(name, mode="dead", container_or_pod="pod")


def absent(name):
    """
    Stops and removes a container by name.
    """
    return _absent_or_dead(name, mode="absent")


def pod_absent(name):
    """
    Stops and removes a pod by name.
    """
    return _absent_or_dead(name, mode="absent", container_or_pod="pod")


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
