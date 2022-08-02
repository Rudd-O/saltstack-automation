# -*- coding: UTF-8 -*-

from __future__ import print_function

import collections
import json
import os
import subprocess
import fcntl
import posix_ipc
import sys


def cmd_with_serialization_lock(cmd, **kwargs):
    with open(os.path.expanduser("~/.qvmpass.lock"), "w+") as x:
        x.write(str(os.getpid()))
        x.flush()
        fcntl.flock(x, fcntl.LOCK_EX)
        try:
            ret = subprocess.check_output(cmd, **kwargs)
            return ret
        finally:
            fcntl.flock(x, fcntl.LOCK_UN)


def cmd_with_serialization(cmd, **kwargs):
    with posix_ipc.Semaphore(
        name="/qvmpass.lock", flags=posix_ipc.O_CREAT, initial_value=6
    ):
        return subprocess.check_output(cmd, **kwargs)


def tree(vm=None):
    a = ["qvm-pass"]
    if vm is not None:
        a.append("-d")
        a.append(vm)
    e = dict(os.environ.items())
    e["LC_ALL"] = "en_US.utf-8"
    lines = cmd_with_serialization(a, env=e, bufsize=0)
    lines = lines.decode("utf-8").splitlines()
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
            name = name[len("\x1b[01;34m"):]
            name = name[: -len("\x1b[0m")]
        elif name.startswith("\x1b[00m"):
            name = name[len("\x1b[00m"):]
            name = name[: -len("\x1b[0m")]
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


def listdir(subdir=None, vm=None):
    t = tree(vm=vm)
    if subdir is None:
        return list(t.keys())
    if hasattr(subdir, "decode") or hasattr(subdir, "encode"):
        subdir = subdir.split(os.path.sep)
    for elm in subdir:
        t = t[elm]
    return list(t.keys())


def get(key, create=True, vm=None):
    # FIXME: uses of get() are tainted by both create=True and the assumption
    # that this returns the very first line without a space at the end, this
    # must be corrected everywhere.
    a = ["qvm-pass"]
    if vm is not None:
        a.append("-d")
        a.append(vm)
    if not (hasattr(key, "decode") or hasattr(key, "encode")):
        key = os.path.sep.join(key)
    if create:
        a.append("get-or-generate")
    a.append("--")
    a.append(key)
    try:
        return cmd_with_serialization(a, universal_newlines=True, bufsize=0)[:-1]
    except subprocess.CalledProcessError as e:
        if e.returncode == 8:
            # FIXME proper error handling: https://github.com/saltstack/salt/issues/43187
            raise KeyError(key)
        raise


def get_multiline(key, vm=None):
    a = ["qvm-pass"]
    if vm is not None:
        a.append("-d")
        a.append(vm)
    if not (hasattr(key, "decode") or hasattr(key, "encode")):
        key = os.path.sep.join(key)
    a.append("--")
    a.append(key)
    try:
        return cmd_with_serialization(["qvm-pass", key], universal_newlines=True, bufsize=0)
    except subprocess.CalledProcessError as e:
        if e.returncode == 8:
            # FIXME proper error handling: https://github.com/saltstack/salt/issues/43187
            raise KeyError(key)
        raise


def get_json(key, vm=None):
    return json.loads(get_multiline(key, vm=vm))


def get_fields(key, vm=None):
    m = get_multiline(key, vm=vm)
    a = m.splitlines(False)
    f = a[0]
    m = a[1:]
    fields = {}
    for w in m:
        try:
            k, v = w.split(":", 1)
        except Exception:
            continue
        v = v.lstrip()
        fields[k] = v
    if "password" not in fields:
        fields["password"] = f
    return fields


if __name__ == "__main__":
    import pprint
    import yaml
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
