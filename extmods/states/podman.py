"""
Various states to help with deployment on Qubes VMs.
"""

import json
import os
import re
import subprocess
from subprocess import check_output as co, CalledProcessError

from shlex import quote
import shlex


def __virtual__():
    return "podman"


def _single(subname, *args, **kwargs):
    ret = __salt__["state.single"](*args, **kwargs)
    try:
        ret = list(ret.values())[0]
    except AttributeError:
        try:
            ret = {
                "changes": {},
                "result": False,
                "comment": ret[0],
            }
        except Exception:
            assert 0, ret
    ret["name"] = subname
    return ret


def _escape_unit(name):
    if not name.endswith(".service"):
        name += ".service"
    return co(["systemd-escape", "-m", "--", name], text=True).rstrip()


def _runas_wrap(cmd, runas=None):
    if not runas:
        return cmd
    return ["su", "-", runas, "-s", "/bin/bash", "-c", shlex.join(cmd)]


def present(name, image, options=None, dryrun=False, enable=None, runas=None, args=None):
    """
    Creates a container with a name, and runs it under systemd.

    If dryrun is specified, the existing properties of the
    container are checked, and changes are returned accordingly
    without making any changes.

    `runas` specifies under what host system user to run the
    container as.
    """
    options = options or []

    try:
        o = co(_runas_wrap(["podman", "container", "inspect", name], runas=runas))
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
    cmd += [] if not args else args

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
                            runas=runas,
                            clean_env=True,
                        )
                    )
            if success():
                a(
                    _single(
                        "Container new",
                        "cmd.run",
                        name=" ".join(quote(x) for x in cmd),
                        runas=runas,
                        clean_env=True,
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
                    runas=runas,
                    clean_env=True,
                )
            )

    if success():
        if not __opts__["test"] or container_exists:

            unit = co(_runas_wrap("podman generate systemd --no-header".split() + [name], runas=runas), text=True)
            if runas:
                unit = unit.replace(f"[Service]", f"[Service]\nUser={runas}")
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


def quadlet_present(
    name,
    image,
    environment=None,
    network=None,
    enable=None,
    runas=None,
    userns=None,
    args=None,
    **kwargs
):
    """
    Creates a container with a name, and deploys it as a podman quadlet.

    If dryrun is specified, the existing properties of the
    container are checked, and changes are returned accordingly
    without making any changes.

    `runas` specifies under what host system user to run the
    container as.
    """
    if runas is None:
        uid = 0
    else:
        uid = __salt__["cmd.run"](f"id {quote(runas)}").split("=")[1].split("(")[0]
    escaped_name = _escape_unit(name)[:-8]
    unit_path = (
        "/etc/containers/systemd/system/%s.container" % escaped_name
    ) if runas is None else (
        "/etc/containers/systemd/users/%s/%s.container" % (uid, escaped_name)
    )

    rets = []
    a, success = rets.append, lambda: not rets or all(
        r["result"] != False for r in rets
    )

    environment = "\n".join([f"Environment={e}" for e in environment]) if environment else ""
    network = f"Network={network}" if network else ""
    userns = f"UserNS={userns}" if userns else ""
    args = f"Exec={(" ".join(quote(q) for q in args))}" if args else ""

    return _single(
        "quadlet creation",
        "file.managed",
        name=unit_path,
        contents=f"""\
[Unit]
Description=Podman container for {name}
Documentation=man:podman-systemd(1)

[Container]
Image={image}
{environment}
{network}
{userns}
{args}

[Install]
WantedBy=default.target
""",
        **kwargs,
    )



from salt.states.service import _get_systemd_only
from salt.exceptions import CommandExecutionError

def mod_watch(
    name,
    sfun=None,
    sig=None,
    reload=False,
    full_restart=False,
    init_delay=None,
    force=False,
    **kwargs
):
    # import pprint
    # assert 0, pprint.pformat((name, sfun, sig, reload, full_restart, init_delay, force, kwargs))

    ret = {"name": name, "changes": {}, "result": True, "comment": ""}
    past_participle = None

    status_kwargs, warnings = _get_systemd_only(__salt__["service.status"], kwargs)
    if warnings:
        _add_warnings(ret, warnings)

    #if sfun == "dead":
    #    verb = "stop"
    #    past_participle = verb + "ped"
    #    if __salt__["service.status"](name, sig, **status_kwargs):
    #        func = __salt__["service.stop"]
    #    else:
    #        ret["result"] = True
    #        ret["comment"] = "Service is already {}".format(past_participle)
    #        return ret
    if sfun == "present":
        name = f"container-{name}"
        ret["name"] = name
        if __salt__["service.status"](name, sig, **status_kwargs):
            if "service.reload" in __salt__ and reload:
                if "service.force_reload" in __salt__ and force:
                    func = __salt__["service.force_reload"]
                    verb = "forcefully reload"
                else:
                    func = __salt__["service.reload"]
                    verb = "reload"
            elif "service.full_restart" in __salt__ and full_restart:
                func = __salt__["service.full_restart"]
                verb = "fully restart"
            else:
                func = __salt__["service.restart"]
                verb = "restart"
        else:
            func = __salt__["service.start"]
            verb = "start"
        if not past_participle:
            past_participle = verb + "ed"
    else:
        ret["comment"] = "Unable to trigger watch for service.{}".format(sfun)
        ret["result"] = False
        return ret

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = "Service is set to be {}".format(past_participle)
        return ret

    if verb == "start" and "service.stop" in __salt__:
        # stop service before start
        __salt__["service.stop"](name)

    func_kwargs, warnings = _get_systemd_only(func, kwargs)
    if warnings:
        _add_warnings(ret, warnings)

    try:
        result = func(name, **func_kwargs)
    except CommandExecutionError as exc:
        ret["result"] = False
        ret["comment"] = exc.strerror
        return ret

    if init_delay:
        time.sleep(init_delay)

    ret["changes"] = {name: result}
    ret["result"] = result
    ret["comment"] = (
        "Service {}".format(past_participle)
        if result
        else "Failed to {} the service".format(verb)
    )
    return ret


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
        if isinstance(v, list):
            v = v[0]
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
            while any(unitl.endswith("\\\n") for unitl in unitls):
                for n, line in enumerate(unitls):
                    if line.endswith("\\\n"):
                        unitls[n] = unitls[n][:-2] + unitls.pop(n+1)
                        break
            execstartline = [n for n, l in enumerate(unitls) if l.startswith("ExecStart=")][0]
            execstopline = [n for n, l in enumerate(unitls) if l.startswith("ExecStop=")][0]
            execstoppostline = [n for n, l in enumerate(unitls) if l.startswith("ExecStopPost=")][0]
            unitls[execstartline] = unitls[execstartline].split("start")[0] + " pod start " + name + "\n"
            unitls[execstopline] = unitls[execstopline].split("stop")[0] + " pod stop " + name + "\n"
            unitls[execstoppostline] = unitls[execstoppostline].split("stop")[0] + " pod stop -i " + name + "\n"
            unitls = [u for u in unitls if not u.startswith("#")]
            for n, u in enumerate(unitls):
                if (
                    u.startswith("Requires=container")
                    or u.startswith("BindsTo=container")
                    or u.startswith("Before=container") 
                    or u.startswith("After=container")
                    or u.startswith("Wants=container")
                ):
                    unitls[n] = "# " + u
            unit = "".join(unitls)
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


def _absent_or_dead(name, mode, container_or_pod="container", runas=None):
    """
    Stops a container by name.
    """
    try:
        o = co(["podman", container_or_pod, "inspect", name])
        container_exists = True
        v = json.loads(o)
        if isinstance(v, list):
            v = v[0]
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

        subcmds = []
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
                        runas=runas,
                        clean_env=True,
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
