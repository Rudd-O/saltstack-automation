import collections
import os
import subprocess
import sys


def __virtual__():
    return "mypkg"


def _rpmlist():
    p = subprocess.check_output(
        ["rpm", "-qa", "--queryformat=%{name} %{version}\n"], universal_newlines=True
    )
    pairs = list(sorted([x.strip().split(" ", 1) for x in p.splitlines() if x.strip()]))
    dkt = collections.OrderedDict()
    for k, v in pairs:
        dkt[k] = v
    return dkt


def _single(subname, *args, **kwargs):
    ret = __salt__["state.single"](*args, **kwargs)
    ret = list(ret.values())[0]
    ret["name"] = subname
    return ret


def installed(name, pkgs=None, version=None):
    if os.access("/usr/bin/qubes-dom0-update", os.X_OK):
        before = _rpmlist()
        pkgs = pkgs or [name]
        if version is not None and len(pkgs) != 1:
            return {
                "name": name,
                "changes": {},
                "result": False,
                "comment": "A version cannot be specified when requesting more than one package to install.",
            }

        if version is None:
            # Optimize the common case.
            missing = [p for p in pkgs if not p in before]
            if __opts__["test"]:
                if missing:
                    return {
                        "name": name,
                        "changes": {
                            "installed": missing,
                        },
                        "result": None,
                        "comment": "Packages %s would be installed."
                        % ", ".join(missing),
                    }
            if not missing:
                return {
                    "name": name,
                    "changes": {},
                    "result": True,
                    "comment": "All packages are already installed.",
                }
        else:
            missing = [pkgs[0] + "-" + version]

        p = subprocess.Popen(
            ["qubes-dom0-update", "-y"] + missing,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        stdout, stderr = p.communicate()
        r = p.wait()
        if r != 0:
            return {
                "name": name,
                "changes": {},
                "result": False,
                "retcode": r,
                "comment": (
                    "Command failed with status code %s." % r
                    + "\nStdout:\n%s" % stdout
                    + "\nStderr:\n%s" % stderr
                ),
                "stdout": stdout,
                "stderr": stderr,
            }
        else:
            after = _rpmlist()
            res = collections.OrderedDict()
            for p in sorted(set(before) | set(after)):
                if not p in before:
                    res[p] = collections.OrderedDict()
                    res[p]["old"] = "-"
                    res[p]["new"] = after[p]
                elif not p in after:
                    res[p] = collections.OrderedDict()
                    res[p]["old"] = before[p]
                    res[p]["new"] = "-"
                elif before[p] != after[p]:
                    res[p] = collections.OrderedDict()
                    res[p]["old"] = before[p]
                    res[p]["new"] = after[p]
            return {
                "name": name,
                "changes": res,
                "retcode": r,
                "result": True,
                "comment": ("Stdout:\n%s" % stdout + "\nStderr:\n%s" % stderr),
                "stdout": stdout,
                "stderr": stderr,
            }
    else:
        return __states__["pkg.installed"](name=name, pkgs=pkgs)


def _dom0_uptodate(name):
    ret = _single(
        name,
        "cmd.run",
        name="qubes-dom0-update -y",
    )
    if ret["result"] in (True, None):
        rex = "Upgrade.*Packages|Installing:|Removing:|Upgrading:|Updating:"
        text = ret.get("changes", {}).get("stdout", "")
        text += ret.get("changes", {}).get("stderr", "")
        if re.search(rex, text):
            pass
        else:
            ret["changes"] = {}
    return ret


def uptodate(name):
    if os.access("/usr/bin/qubes-dom0-update", os.X_OK):
        _dom0_uptodate(name)
    else:
        return __states__["pkg.uptodate"](name=name)
