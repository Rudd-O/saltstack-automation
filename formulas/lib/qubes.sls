#!pyobjects

from salt://lib/defs.sls import Perms

try:
    from shlex import quote
except ImportError:
    from pipes import quote


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


def RpcPolicy(name, contents):
    n = "/etc/qubes-rpc/policy/" + name
    return File.managed(
        n,
        contents=contents,
        user="root",
        group="qubes",
        **Perms.dir
    ).requisite
