import os
from shlex import quote


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


def present(name, user, private, public, filename=None):
    """Deploys an SSH keypair on the system for the specified user,
    deploying both the private and the public key with the right
    permissions.

    If `filename` is None (the default), the name of the state is used as
    the filename.

    If the filename contains no directory components, then the ~/.ssh
    directory is assumed for the location of the files.
    """
    if filename is None:
        filename = name
    if os.path.basename(filename) == filename:
        sshbase = os.path.expanduser("~" + user + "/.ssh")
        filename = os.path.join(sshbase, filename)

    rets = []
    a, success, lastchanged = (
        rets.append,
        lambda: not rets or all(r["result"] != False for r in rets),
        lambda: rets and rets[-1]["changes"],
    )

    a(
        _single(
            os.path.dirname(filename),
            "file.directory",
            name=os.path.dirname(filename),
            user=user,
            mode="0700",
        )
    )
    if success() or __opts__["test"]:
        a(
            _single(
                filename,
                "file.managed",
                name=filename,
                contents=private,
                user=user,
                mode="0600",
                makedirs=True,
            )
        )
    if success() or __opts__["test"]:
        a(
            _single(
                filename + ".pub",
                "file.managed",
                name=filename + ".pub",
                contents=public,
                user=user,
                mode="0644",
                makedirs=True,
            )
        )

    return dict(
        name=name,
        result=success(),
        comment="\n".join(r["comment"] for r in rets),
        changes=dict((r["name"], r["changes"]) for r in rets if r["changes"]),
    )
