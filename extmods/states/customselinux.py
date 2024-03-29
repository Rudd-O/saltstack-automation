import os
from shlex import quote
import subprocess


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


def policy_module_present(name, source):
    rets = []
    a, success, lastchanged = (
        rets.append,
        lambda: not rets or all(r["result"] != False for r in rets),
        lambda: rets and rets[-1]["changes"],
    )
    fname = os.path.basename(name)
    a(
        _single(
            f"Deploy policy module {fname}",
            "file.managed",
            name=f"/etc/selinux/targeted/local/{fname}.te",
            makedirs=True,
            source=source,
        )
    )
    if success() and lastchanged():
        qfname = quote(fname)
        cmd = (
            """
set -e
cd /etc/selinux/targeted/local
(
    rm -f %(qfname)s.mod
    checkmodule -M -m -o %(qfname)s.mod %(qfname)s.te
    semodule_package -o %(qfname)s.pp -m %(qfname)s.mod
) || {
    r=$?
    rm -f %(qfname)s.te
    exit $?
}
"""
            % locals()
        )
        a(
            _single(
                f"Compile policy module {fname}",
                "cmd.run",
                name=cmd,
            )
        )
    if success():
        if not __opts__["test"]:
            try:
                selinuxenabled = subprocess.call("selinuxenabled")
                if selinuxenabled == 1:
                    selinuxenabled = False
                else:
                    selinuxenabled = True
            except OSError:
                selinuxenabled = False
            if selinuxenabled:
                a(
                    _single(
                        f"Install policy module {fname}",
                        "selinux.module",
                        name=fname,
                        install=True,
                        source=f"/etc/selinux/targeted/local/{fname}.pp",
                    )
                )
            else:
                a(
                    _single(
                        f"Skipping install of policy module {fname} because SELinux is not enabled",
                        "test.nop",
                        name=fname,
                    )
                )
    else:
        _single(
            f"Remove bad modules",
            "cmd.run",
            name=f"cd /etc/selinux/targeted/local && rm -f {qfname}-new.pp {qfname}.pp {qfname}.mod {qfname}.te",
        )

    return dict(
        name=name,
        result=success(),
        comment="\n".join(r["comment"] for r in rets),
        changes=dict((r["name"], r["changes"]) for r in rets if r["changes"]),
    )
