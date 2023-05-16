#!pyobjects

from salt://lib/defs.sls import Perms

try:
    from shlex import quote
except ImportError:
    from pipes import quote


# FIXME replace all these ugly functions with a Python object called Me
# or I, tht way I can say stuff like I.am.dom0.
def dom0():
    return grains('qubes:vm_type') == "AdminVM"


def fully_persistent_or_physical():
    return grains('qubes:persistence') in ('full', '')


def fully_persistent():
    return grains('qubes:persistence') in ('full',)


def rw_only_or_physical():
    return grains('qubes:persistence') in ('rw-only', '')


def template():
    return grains('qubes:vm_type') == "TemplateVM"


def physical():
    return grains('qubes:persistence') in ('')


def updateable():
    # This is always true for physical machines.
    return grains('qubes:updateable', False)


def rw_only():
    return grains('qubes:persistence') in ('rw-only',)


def OldRpcPolicy(name, contents=None):
    n = "/etc/qubes-rpc/policy/" + name
    if not contents:
        return File.absent(n).requisite
    return File.managed(
        n,
        contents=contents,
        user="root",
        group="qubes",
        **Perms.dir
    ).requisite

def NewRpcPolicy(name, contents, **kwargs):
    if not contents:
        return File.absent(
            f"/etc/qubes/policy.d/{name}.policy",
            **kwargs,
        )
    return File.managed(
        f"/etc/qubes/policy.d/{name}.policy",
        contents=contents,
        mode="0664",
        user="root",
        group="qubes",
        **kwargs,
    )
