# -*- coding: UTF-8 -*-

from __future__ import print_function

import collections
import cryptography.fernet
import hashlib
import json
import os
import subprocess
import threading
import fcntl
import posix_ipc
import sys


_NO_DEFAULT = object()
_TREE = object()


def _cmd_with_serialization_lock(cmd, **kwargs):
    with open(os.path.expanduser("~/.qvmpass.lock"), "w+") as x:
        x.write(str(os.getpid()))
        x.flush()
        fcntl.flock(x, fcntl.LOCK_EX)
        try:
            ret = subprocess.check_output(cmd, **kwargs)
            return ret
        finally:
            fcntl.flock(x, fcntl.LOCK_UN)


def _cmd_with_serialization(cmd, **kwargs):
    return subprocess.check_output(cmd, **kwargs)
    # the rest is currently disabled  FIXME
    with posix_ipc.Semaphore(
        name="/qvmpass.lock", flags=posix_ipc.O_CREAT, initial_value=6
    ):
        return subprocess.check_output(cmd, **kwargs)


def _get_keyring_id(name):
    try:
        o = subprocess.check_output(["keyctl", "show"], text=True)
        return [
            l.strip().split()[0]
            for l in o.splitlines()
            if l.endswith(f"keyring: {name}")
        ][0]
    except IndexError:
        return None


def _new_keyring(parent_keyring_id, keyring_name):
    return subprocess.check_output(
        ["keyctl", "newring", keyring_name, parent_keyring_id]
    )[:-1]


def _get_user_key_id(keyring_id, name):
    try:
        o = subprocess.check_output(["keyctl", "list", keyring_id], text=True)
        return [
            l.strip().split(":")[0]
            for l in o.splitlines()
            if l.endswith(f"user: {name}")
        ][0]
    except IndexError:
        return None


def _save_user_key(keyring_id, key_name, key_material):
    return subprocess.check_output(
        ["keyctl", "padd", "user", key_name, keyring_id],
        input=key_material,
    )[:-1]


def _get_key(key_id):
    return subprocess.check_output(["keyctl", "pipe", key_id])


def _qvmpass_get(key, vm=None, text=True, generate=False, cache=True):
    if generate:
        assert key is not _TREE

    def query_qvmpass(text):
        cmd = ["qvm-pass"] + (["-d", vm] if vm else []) + (["get-or-generate"] if generate else []) + (["--", key] if key is not _TREE else [])
        env = dict(os.environ.items())
        if text:
            env["LC_ALL"] = "en_US.utf-8"
        return _cmd_with_serialization(
            cmd,
            universal_newlines=text,
            env=env,
            bufsize=0,
        )

    if not cache:
        return query_qvmpass(text)

    lock_folder = f"/run/user/{os.getuid()}/qvmpass-cache/"
    os.makedirs(lock_folder, mode=0o700, exist_ok=True)
    with open(os.path.join(lock_folder, "qvmpass.lock"), "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

        qvmpass_keyring = (
            _get_keyring_id("qvmpass-cache")
            or
            _new_keyring(_get_keyring_id("_ses"), "qvmpass-cache")
        )

        encryption_key = _get_key(
            _get_user_key_id(qvmpass_keyring, "qvmpass-cache-key")
            or 
            _save_user_key(qvmpass_keyring, "qvmpass-cache-key", cryptography.fernet.Fernet.generate_key())
        )

        fcntl.flock(lock, fcntl.LOCK_UN)

    if key is not _TREE:
        abskey = os.path.join("get", os.path.abspath("/" + key).lstrip(os.path.sep))
        abskey = f"{abskey}-{vm}"
    else:
        abskey = "tree"

    cache_key = hashlib.md5(abskey.encode("utf-8") + encryption_key).hexdigest()
    cryptor = cryptography.fernet.Fernet(encryption_key)

    with open(os.path.join(lock_folder, cache_key), "a+b") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        data = f.read()
        if data:
            fcntl.flock(f, fcntl.LOCK_UN)
            res = cryptor.decrypt(data)
        else:
            res = query_qvmpass(False)
            f.seek(0)
            f.truncate()
            f.write(cryptor.encrypt(res))
            fcntl.flock(f, fcntl.LOCK_UN)

    return res.decode("utf-8") if text else res


def _qvmpass_get_or_generate(key, vm=None, text=True):
    return _qvmpass_get(key, vm, text, generate=True)


def _qvmpass_tree(vm=None):
    return _qvmpass_get(_TREE, vm)



def tree(vm=None):
    lines = _qvmpass_tree(vm).splitlines()
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


def get(key, create=True, vm=None, default=_NO_DEFAULT):
    # FIXME: uses of get() are tainted by both create=True and the assumption
    # that this returns the very first line without a space at the end, this
    # must be corrected everywhere.
    f = _qvmpass_get_or_generate if create else _qvmpass_get
    if not (hasattr(key, "decode") or hasattr(key, "encode")):
        key = os.path.sep.join(key)
    try:
        return f(key, vm, text=True)[:-1]
    except subprocess.CalledProcessError as e:
        if e.returncode == 8:
            # FIXME proper error handling: https://github.com/saltstack/salt/issues/43187
            if default != _NO_DEFAULT:
                return default
            raise KeyError(key)
        raise


def get_multiline(key, vm=None, default=_NO_DEFAULT):
    f = _qvmpass_get
    if not (hasattr(key, "decode") or hasattr(key, "encode")):
        key = os.path.sep.join(key)
    try:
        return f(key, text=True)
    except subprocess.CalledProcessError as e:
        if e.returncode == 8:
            # FIXME proper error handling: https://github.com/saltstack/salt/issues/43187
            if default != _NO_DEFAULT:
                return default
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
    import sys
    import concurrent.futures
    import time


    print(tree())
    print(get('Machines/ap/ubus/assistant'))
    sys.exit(0)

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
