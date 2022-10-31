# -*- coding: UTF-8 -*-

from __future__ import print_function

import collections
import json
import os
import subprocess
import fcntl
import sys


class _RaiseExc(object): pass


def _cmd_with_serialization(cmd, **kwargs):
    return subprocess.check_output(cmd, **kwargs)


def tree():
    a = ["pass"]
    e = dict(os.environ.items())
    e["LC_ALL"] = "en_US.utf-8"
    # lines = _cmd_with_serialization(a, env=e, bufsize=0)
    # lines = lines.decode("utf-8").splitlines()
    # demo lines with colorization = ['Password Store', '├── \x1b[01;34mbin\x1b[00m', '│\xa0\xa0 ├── \x1b[01;32mpass-import-keys\x1b[00m', '│\xa0\xa0 └── \x1b[01;32mpass-reencrypt\x1b[00m', '├── \x1b[01;34mEmail\x1b[00m', '│\xa0\xa0 ├── \x1b[01;34mDKIM\x1b[00m', '│\xa0\xa0 │\xa0\xa0 └── \x1b[01;34mfuto.org\x1b[00m', '│\xa0\xa0 │\xa0\xa0     ├── default.private', '│\xa0\xa0 │\xa0\xa0     └── default.txt', '│\xa0\xa0 └── \x1b[01;34mRole accounts\x1b[00m', '│\xa0\xa0     └── webserver', '├── \x1b[01;34mGitlab\x1b[00m', '│\xa0\xa0 └── \x1b[01;34mdevops\x1b[00m', '│\xa0\xa0     └── \x1b[01;34mploneserver\x1b[00m', '│\xa0\xa0         └── Podman deploy on Linux servers', '├── \x1b[01;34mGnuPG team pubkeys\x1b[00m', '│\xa0\xa0 ├── aidan@dunlap.ai', '│\xa0\xa0 ├── \x1b[01;32maidan@dunlap.ai.asc\x1b[00m', '│\xa0\xa0 ├── eron@futo.org.asc', '│\xa0\xa0 ├── harpo@futo.org.asc', '│\xa0\xa0 ├── \x1b[01;32mIanKey+ian@futo.org.asc\x1b[00m', '│\xa0\xa0 ├── \x1b[01;32mpavel@machalek.io.asc\x1b[00m', '│\xa0\xa0 ├── \x1b[01;32mrudd-o+futolaptop@rudd-o.com.asc\x1b[00m', '│\xa0\xa0 └── \x1b[01;32mrudd-o+futo@rudd-o.com.asc\x1b[00m', '├── \x1b[01;34mMatrix\x1b[00m', '│\xa0\xa0 ├── \x1b[01;34mPostgreSQL\x1b[00m', '│\xa0\xa0 │\xa0\xa0 └── credentials', '│\xa0\xa0 ├── \x1b[01;34mSynapse\x1b[00m', '│\xa0\xa0 │\xa0\xa0 ├── registration shared secret', '│\xa0\xa0 │\xa0\xa0 └── TURN auth secret', '│\xa0\xa0 └── \x1b[01;34mUsers\x1b[00m', '│\xa0\xa0     ├── cvwright', '│\xa0\xa0     ├── eron', '│\xa0\xa0     ├── ian', '│\xa0\xa0     ├── rudd-o', '│\xa0\xa0     ├── tester1', '│\xa0\xa0     ├── tester2', '│\xa0\xa0     └── xyzproto', '├── \x1b[40;31;01mpassword-store\x1b[00m -> \x1b[00mpassword-store/\x1b[00m', '├── \x1b[01;32mREADME.md\x1b[00m', '├── \x1b[01;34mRPM\x1b[00m', '│\xa0\xa0 └── repo.rudd-o.com signing key', '├── \x1b[01;34mTelemetry\x1b[00m', '│\xa0\xa0 ├── Grafana', '│\xa0\xa0 └── Web access', '├── \x1b[01;34mWeb sites\x1b[00m', '│\xa0\xa0 ├── Plone administrator user for master deployment', '│\xa0\xa0 ├── Plone administrator user for staging deployment', '│\xa0\xa0 └── Proxy purge key', '└── \x1b[01;34mWireguard\x1b[00m', '    └── \x1b[01;34mcircles\x1b[00m', '        ├── fedora-s-4vcpu-8gb-sfo3-01', '        └── fedora-s-4vcpu-8gb-sfo3-02']
    # for line in lines:
    #     print(line)
    # import sys ; sys.exit(0)
    currdepth = 0
    items = {}
    itemstack = []
    lastname = None
    for line in lines:
        depth = line.find(u"─ ") - 2
        if depth == -3:
            # root item
            continue
        name = line[depth + 4 :]
        if name.startswith("\x1b[01;34m"):
            name = name[len("\x1b[01;34m") :]
            name = name[: -len("\x1b[0m")]
            if name.endswith("\x1b"):
                name = name[:-1]
        if name.startswith("\x1b[40;31;01m"):
            # broken symlink
            continue
        if name.startswith("\x1b[01;32m"):
            name = name[len("\x1b[01;32m") :]
            name = name[: -len("\x1b[0m")]
            if name.endswith("\x1b"):
                name = name[:-1]
        if depth > currdepth:
            itemstack.append(items)
            items = items[lastname]
            items[name] = {}
        elif depth == currdepth:
            items[name] = {}
        elif depth < currdepth:
            while depth < currdepth:
                items = itemstack.pop()
                currdepth = currdepth - 4
            items[name] = {}
        lastname = name
        currdepth = depth
    while itemstack:
        items = itemstack.pop()
    return items


def listdir(subdir=None):
    t = tree()
    if subdir is None:
        return list(t.keys())
    if hasattr(subdir, "decode") or hasattr(subdir, "encode"):
        subdir = subdir.split(os.path.sep)
    for elm in subdir:
        t = t[elm]
    return list(t.keys())


def get_multiline(key):
    a = ["pass"]
    a.append("--")
    a.append(key)
    return _cmd_with_serialization(["pass", key], universal_newlines=True, bufsize=0)


def get(key):
    """Gets the first line of a password."""
    a = ["pass"]
    if not (hasattr(key, "decode") or hasattr(key, "encode")):
        key = os.path.sep.join(key)
    a.append("--")
    a.append(key)
    d = get_multiline(key)
    return d.splitlines()[0]


def get_field(key, name, default=_RaiseExc()):
    """Gets the named field of a password stored in format key: value.

    If no default is specified, an exception is raised.
    """
    a = ["pass"]
    if not (hasattr(key, "decode") or hasattr(key, "encode")):
        key = os.path.sep.join(key)
    a.append("--")
    a.append(key)
    d = get_multiline(key)
    fields = [x.split(":", 1) for x in d.splitlines()]
    for f in fields:
        if len(f) < 2: continue
        if f[0] == name:
            return f[1].lstrip()
    if isinstance(default, _RaiseExc):
        raise KeyError("Password %r does not contain field %r" % (key, name))
    return None


def get_json(key):
    return json.loads(get_multiline(key))


if __name__ == "__main__":
    import sys
    print(listdir())
    sys.exit(0)
    import pprint
    import concurrent.futures
    import time

    executor = concurrent.futures.ThreadPoolExecutor(25)
    futures = []
    start = time.time()
    for x in range(25):
        futures.append(executor.submit(tree))
    for future in concurrent.futures.as_completed(futures):
        sys.stdout.write("Getting result...")
        r = str(future.result()).splitlines()[0][:80] + "..."
        print(r)
    print("Total time: %.3f" % (time.time() - start))
