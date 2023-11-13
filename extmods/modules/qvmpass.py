# -*- coding: UTF-8 -*-

from __future__ import print_function

import collections
import cryptography.fernet
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


def _qvmpass_get(key, vm=None, text=True, generate=False, cache=True):
    if generate:
        assert key is not _TREE

    def query_qvmpass():
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
        return query_qvmpass()

    basepath = f"/run/user/{os.getuid()}/qvmpass-cache/"
    os.makedirs(basepath, mode=0o700, exist_ok=True)
    with open(os.path.join(basepath, "qvmpass.lock"), "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        lock.seek(0)
        encryption_key_id = lock.read()
        try:
            encryption_key = subprocess.check_output(["keyctl", "print", encryption_key_id])[:-1]
        except subprocess.CalledProcessError:
            encryption_key = cryptography.fernet.Fernet.generate_key()
            keyring_id = [
                l.strip().split()[0]
                for l in subprocess.check_output(["keyctl", "show"], text=True).splitlines()
                if f"_uid.{os.getuid()}" in l
            ][0]
            p = subprocess.run(["keyctl", "padd", "user", "qvmpass-cache", keyring_id], input=encryption_key, check=True, capture_output=True)
            encryption_key_id = p.stdout.decode("utf-8").splitlines()[0]
            lock.seek(0)
            lock.truncate()
            lock.write(str(encryption_key_id))
            lock.flush()
        cryptor = cryptography.fernet.Fernet(encryption_key)
        try:
            if key is not _TREE:
                abskey = os.path.abspath("/" + key)[len(os.path.sep):]
                path = f"{basepath}/get/{abskey}"
            else:
                path = f"{basepath}/tree"
            folder = os.path.dirname(path)
            os.makedirs(folder, mode=0o700, exist_ok=True)
            try:
                with open(path, "rb") as f:
                    encrypted_res = f.read()
                    bytes_res = cryptor.decrypt(encrypted_res)
                    res = bytes_res.decode("utf-8") if text else bytes_res
            except (FileNotFoundError, cryptography.fernet.InvalidToken):
                res = query_qvmpass()
                tmpname = "." + os.path.basename(path) + "." + str(os.getpid()) + "." + str(threading.get_ident())
                tmppath = os.path.join(folder, tmpname)
                try:
                    with open(tmppath, "wb") as f:
                        bytes_res = res.encode("utf-8") if text else res
                        encrypted_res = cryptor.encrypt(bytes_res)
                        f.write(encrypted_res)
                except Exception:
                    os.unlink(tmppath)
                    raise
                os.rename(tmppath, path)
            return res
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


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
    print(get('Machines/openwrt/ubus/assistant'))
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
