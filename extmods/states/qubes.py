"""
Various states to help with deployment on Qubes VMs.
"""

import re
import os
import subprocess

from shlex import quote


def __virtual__():
    return "qubes"


def _mimic(tgtdict, srcdict):
    for k in "result comment changes".split():
        if k in srcdict:
            tgtdict[k] = srcdict[k]
    return tgtdict


def _mimic_from_rets(ret, rets):
    if rets:
        return _mimic(
            ret,
            {
                "result": False if any(r["result"] is False for r in rets) else None if any(r["result"] is False for r in rets) else True,
                "comment": "\n".join(r["comment"] for r in rets if "comment" in r),
                "changes": dict(
                    (r["name"], r["changes"]) for r in rets if r["changes"]
                ),
            },
        )
    else:
        ret["result"] = True 
        return ret


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

    directories = [
        d for d in directories
        if not d.startswith("/rw/")
        and not d.startswith("/home/")
    ]
    if not directories:
        return _mimic(
            ret,
            {
                "result": True,
                "comment": "Nothing to do (none of the specified directories are outside /rw or /home).",
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

    rets = []

    rets.append(_single(
        "bind-dirs directory",
        "file.directory",
        name="/rw/config/qubes-bind-dirs.d",
        mode="0755",
        user="root",
        group="root",
    ))
    if rets[-1]["result"] is False:
        return _mimic_from_rets(ret, rets)

    for directory in directories:
        rw_bind_dir_parent = os.path.dirname(os.path.join("/rw/bind-dirs", directory.lstrip("/")))
        rets.append(_single(
            rw_bind_dir_parent,
            "file.directory",
            name=rw_bind_dir_parent,
            makedirs=True,
        ))
        if rets[-1]["result"] is False:
            return _mimic_from_rets(ret, rets)

    name = name + ".conf"
    id_ = "/rw/config/qubes-bind-dirs.d/%s" % name
    c = "\n".join("binds+=( %s )" % quote(d) for d in directories)
    rets.append(_single(
        "bind-dirs file",
        "file.managed",
        name=id_,
        mode="0644",
        user="root",
        group="root",
        contents=c,
    ))
    if rets[-1]["result"] is False:
        return _mimic_from_rets(ret, rets)

    if any(r["changes"] for r in rets) or any(not os.path.ismount(d) for d in directories):
        rets.append(_single(
            "bind-dirs.sh",
            "cmd.run",
            name="/usr/lib/qubes/init/bind-dirs.sh",
        ))
        if rets[-1]["result"] is False:
            return _mimic_from_rets(ret, rets)
    else:
        rets.append({"result": True, "comment": "No need to reload bind dirs", "changes": {}})

    return _mimic_from_rets(ret, rets)


def unbind_dirs(name, directories):
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

    rets = []
    for directory in directories:
        if os.path.ismount(directory):
            rets.append(
                _single(
                    f"mount for {directory}",
                    "mount.unmounted",
                    name=directory,
                )
            )
            if rets[-1]["result"] is False:
                return _mimic_from_rets(ret, rets)

    name = name + ".conf"
    id_ = "/rw/config/qubes-bind-dirs.d/%s" % name
    c = "\n".join("binds+=( %s )" % quote(d) for d in directories)
    rets.append(
        _single(
            "bind-dirs file",
            "file.absent",
            name=id_,
        )
    )
    if rets[-1]["result"] is False:
        return _mimic_from_rets(ret, rets)

    return _mimic_from_rets(ret, rets)


def _updateable_qubes_vm():
    return __salt__["grains.get"]("qubes:updateable") and __salt__["grains.get"]("qubes:vm_type")


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
    if scope not in ["system", "user"]:
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

    if _updateable_qubes_vm():
        # Qubes VM.  Updateable (template or standalone).
        pass
    else:
        # Nothing to do (not a Qubes OS VM).
        return ret1

    types = [
        "service", "timer", "socket", "device", "mount", "scope",
        "automount", "swap", "target", "path", "slice",
    ]
    service_to_extend = (
        name if any(name.endswith(".%s" %t) for t in types)
        else name + ".service"
    )
    ret2 = _single(
        "qubify service",
        "file.managed",
        name="/etc/systemd/%s/%s.d/qubes.conf" % (scope, service_to_extend),
        contents="""[Unit]
ConditionPathExists=/var/run/qubes-service/%s
"""
        % qubes_service_name,
        user="root",
        group="root",
        mode="0644",
        makedirs=True,
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


def disable_dom0_managed_service(
    name, scope="system", qubes_service_name=None, disable=False
):
    """
    Remove mark of a systemd service as managed by Qubes OS.

    See https://dev.qubes-os.org/projects/core-admin-client/en/latest/manpages/qvm-service.html
    for more information.
    """
    if qubes_service_name is None:
        qubes_service_name = name
    if scope != "system":
        raise NotImplementedError("The scope %r is not implemented yet" % scope)

    ret = dict(name=name, result=False, changes={}, comment="")

    if disable:
        ret1 = _single(
            "disable service",
            "service.disabled",
            name=name,
        )

        if ret1["result"] is False:
            return ret1
    else:
        ret1 = dict(
            name=name, result=True, changes={}, comment="Service explicitly not disabled"
        )

    if _updateable_qubes_vm():
        # Qubes VM.  Updateable (template or standalone).
        pass
    else:
        # Nothing to do (not a Qubes OS VM).
        return ret1

    types = [
        "service", "timer", "socket", "device", "mount", "scope",
        "automount", "swap", "target", "path", "slice",
    ]
    service_to_extend = (
        name if any(name.endswith(".%s" %t) for t in types)
        else name + ".service"
    )
    ret2 = _single(
        "unqubify service",
        "file.absent",
        name="/etc/systemd/%s/%s.d/qubes.conf" % (scope, service_to_extend),
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


def qvm_service(name, vms, action, services=None):
    ret = dict(name=name, result=False, changes={}, comment="")

    svcs = [name]
    if services:
        svcs = services

    if not isinstance(vms, list):
        vms = [vms]

    current_service_state = {}
    for vm in vms:
        try:
            output = subprocess.check_output(["qvm-service", "--", vm], stderr=subprocess.STDOUT, text=True)
        except Exception as e:
            ret["comment"] = f"qvm-service failed ({e}):\n{e.output.strip()}"

        current_service_state_for_vm = [
            line.split() for line
            in output.splitlines()
            if line.strip()
        ]
        try:
            current_service_state[vm] = {svc: st for svc, st in current_service_state_for_vm}
        except Exception: assert 0, current

    rets = []
    for vm, current_service_state_for_vm in current_service_state.items():
        for service in svcs:
            if action is True:
                if current_service_state_for_vm.get(service) == "on":
                    continue
                rets.append(_single(
                    f"Enable {service} for {vm}",
                    "cmd.run",
                    name=f"qvm-service -e -- {quote(vm)} {quote(service)}",
                ))
            elif action is False:
                if current_service_state_for_vm.get(service) == "off":
                    continue
                rets.append(_single(
                    f"Disable {service} for {vm}",
                    "cmd.run",
                    name=f"qvm-service -d -- {quote(vm)} {quote(service)}",
                ))
            elif action is None:
                if current_service_state_for_vm.get(service) is None:
                    continue
                rets.append(_single(
                    f"Unset {service} for {vm}",
                    "cmd.run",
                    name=f"qvm-service -D -- {quote(vm)} {quote(service)}",
                ))
            else:
                assert 0, f"not reached: state = {action}"
    
    return _mimic_from_rets(ret, rets)
