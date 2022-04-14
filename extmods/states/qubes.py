"""
Various states to help with deployment on Qubes VMs.
"""

import re
import os

try:
    from shlex import quote
except ImportError:
    from pipes import quote


def __virtual__():
    return "qubes"


def _mimic(tgtdict, srcdict):
    for k in "result comment changes".split():
        if k in srcdict:
            tgtdict[k] = srcdict[k]
    return tgtdict


def _single(subname, *args, **kwargs):
    ret = __salt__["state.single"](*args, **kwargs)
    ret = list(ret.values())[0]
    ret["name"] = subname
    return ret


def bind_dirs(name, directories):
    """
    Bind mounts a set of directories on an AppVM, to preserve changes of
    files within it between reboots.

    Only has an effect on AppVMs with volatile root file systems.

    Always create the folder or file before binding.  That is, this state
    must depend on the files it will be binding.

    See https://www.qubes-os.org/doc/bind-dirs/ for more information.
    """
    if not hasattr(directories, "append"):
        directories = [directories]
    ret = dict(name=name, result=False, changes={}, comment="")
    if __salt__["grains.get"]("qubes:persistence") != "rw-only":
        return _mimic(
            ret,
            {
                "result": True,
                "comment": "Nothing to do (not a Qubes OS AppVM with ephemeral root).",
            },
        )

    try:
        assert os.path.basename(name) == name, (
            "The configuration name %r is not a base file name." % name
        )
        assert os.path.isdir(
            "/rw/config"
        ), "The directory /rw/config does not exist on the target."
        notabspath = [d for d in directories if os.path.abspath(d) != d]
        assert not notabspath, (
            "The following directories are not absolute paths: %s" % notabspath
        )
        inrw = [
            d for d in directories if (d == "/rw/config" or d.startswith("/rw/config/"))
        ]
        assert not inrw, (
            "The following directories reside in /rw/config and are not legitimate for this use: %s"
            % inrw
        )
    except AssertionError as e:
        return _mimic(ret, {"comment": str(e)})

    ret1 = _single(
        "bind-dirs directory",
        "file.directory",
        name="/rw/config/qubes-bind-dirs.d",
        mode="0755",
        user="root",
        group="root",
    )

    if ret1["result"] is False:
        return _mimic(ret, ret1)

    name = name + ".conf"
    id_ = "/rw/config/qubes-bind-dirs.d/%s" % name
    c = "\n".join("binds+=( %s )" % quote(d) for d in directories)
    ret2 = _single(
        "bind-dirs file",
        "file.managed",
        name=id_,
        mode="0644",
        user="root",
        group="root",
        contents=c,
    )

    if ret2["result"] is False:
        return _mimic(ret, ret2)

    if ret2["changes"] or any(not os.path.ismount(d) for d in directories):
        ret3 = _single(
            "bind-dirs.sh",
            "cmd.run",
            name="/usr/lib/qubes/init/bind-dirs.sh",
        )

        if ret3["result"] is False:
            return _mimic(ret, ret3)
    else:
        ret3 = {"result": True, "comment": "No need to reload bind dirs", "changes": {}}

    return _mimic(
        ret,
        {
            "result": ret3["result"],
            "comment": "\n".join([r["comment"] for r in [ret1, ret2, ret3]]),
            "changes": dict(
                (r["name"], r["changes"]) for r in [ret1, ret2, ret3] if r["changes"]
            ),
        },
    )


def enable_dom0_managed_service(
    name, scope="system", qubes_service_name=None, enable=True
):
    """
    Mark a systemd service as managed by Qubes OS, and enable the
    service.  In other words, if the service is not enabled through
    qvm-service in dom0, the service will not be started on boot.

    Only makes service changes in TemplateVMs.  In other types of VMs
    or machines, it is equivalent to the service.enabled state.

    If enable is False, the service will not be enabled, only qubified.

    See https://dev.qubes-os.org/projects/core-admin-client/en/latest/manpages/qvm-service.html
    for more information.
    """
    if qubes_service_name is None:
        qubes_service_name = name
    if scope != "system":
        raise NotImplementedError("The scope %r is not implemented yet" % scope)

    ret = dict(name=name, result=False, changes={}, comment="")

    if enable:
        ret1 = _single(
            "enable service",
            "service.enabled",
            name=name,
        )

        if ret1["result"] is False:
            return ret1
    else:
        ret1 = dict(
            name=name, result=True, changes={}, comment="Service explicitly not enabled"
        )

    if __salt__["grains.get"]("qubes:vm_type", "").lower() != "TemplateVM".lower():
        # Nothing to do (not a Qubes OS TemplateVM).
        return ret1

    ret2 = _single(
        "qubify service",
        "file.managed",
        name="/etc/systemd/%s/%s.service.d/qubes.conf" % (scope, name),
        contents="""[Unit]
ConditionPathExists=/var/run/qubes-service/%s
"""
        % qubes_service_name,
        user="root",
        group="root",
        mode="0644",
    )

    if ret2["result"] is False:
        return ret2

    return _mimic(
        ret,
        {
            "result": ret2["result"],
            "comment": "\n".join([ret1["comment"], ret2["comment"]]),
            "changes": dict(
                (r["name"], r["changes"]) for r in [ret1, ret2] if r["changes"]
            ),
        },
    )
