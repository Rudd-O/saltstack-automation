import contextlib
import json
import subprocess
import tempfile

from shlex import quote, split


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


@contextlib.contextmanager
def _keyfile(existing_keyfile=None, existing_passphrase=None, tmpdir=None):
    if existing_keyfile:
        with open(existing_keyfile) as f:
            data = f.read()
    else:
        data = b"" if not existing_passphrase else existing_passphrase.encode("utf-8")
    with tempfile.NamedTemporaryFile(dir=tmpdir, mode="wb", prefix="nbde-") as f:
        f.write(data)
        f.flush()
        yield f.name


def enroll_via_keyfile(name, keyfile, existing_keyfile=None, existing_passphrase=None, tmpdir=None, *args, **kwargs):
    """
    Add a keyfile to a LUKS device.
    
    Parameters:

    * name: the path to the device
    * keyfile: the file containing a key to be added to the device
    * existing_keyfile: (optional) a keyfile with a key that can decrypt the device
    * existing_passphrase: (optional) a passphrase that can decrypt the device
    * tmpdir: (optional) a directory for temporary LUKS key files

    If modifications must be done, either existing_keyfile or existing_passphrase
    must be supplied.  If the device already has keyfile added to it, neither
    are necessary.  Any key material is securely written to a temporary file in
    the system-wide temporary directory unless specified otherwise.
    """
    quoted_path = quote(name)
    quoted_keyfile = quote(keyfile)
    

    with _keyfile(existing_keyfile, existing_passphrase, tmpdir) as k:
        qexistingkeyfile = quote(k)
        return _single(
            name,
            "cmd.run",
            name=f"""
                changed=no
                set -e
                if test -f {quoted_keyfile}
                then
                    echo Crypto key {quoted_keyfile} already exists. >&2
                else
                    echo Creating {quoted_keyfile} from random data. >&2
                    umask 077
                    mkdir -p -m 0700 $(dirname {quoted_keyfile})
                    dd if=/dev/random bs=32 count=1 of={quoted_keyfile} >&2
                    changed=yes
                fi
                if cryptsetup luksOpen --test-passphrase --key-file {quoted_keyfile} {quoted_path} >&2
                then
                    echo Device {quoted_path} decrypts correctly. >&2
                else
                    if [ ! -f {qexistingkeyfile} ] || [ $(stat -c %s {qexistingkeyfile}) = 0 ]
                    then
                        echo To enroll device {quoted_path}, an existing_keyfile or existing_passphrase is needed >&2
                        exit 16
                    fi
                    echo Enrolling device {quoted_path}. >&2
                    changed=yes
                    echo abc >&2
                    cat {qexistingkeyfile} >&2
                    echo def >&2
                    cryptsetup luksAddKey -y --key-file {qexistingkeyfile} {quoted_path} {quoted_keyfile} >&2
                    echo Testing enroll of {quoted_path}. >&2
                    cryptsetup luksOpen --test-passphrase --key-file {quoted_keyfile} {quoted_path} >&2
                    echo Enrolled device {quoted_path}. >&2
                fi
                echo
                if [ "$changed" = "yes" ] ; then echo changed=$changed ; fi
            """,
            stateful=True,
            *args,
            **kwargs,
        )


def enroll_via_tang_server(name, url, existing_keyfile=None, existing_passphrase=None, tmpdir=None, *args, **kwargs):
    """
    Add a Tang + Clevis binding to a LUKS device.
    
    Parameters:

    * name: the path to the device
    * existing_keyfile: (optional) a keyfile with a key that can decrypt the device
    * existing_passphrase: (optional) a passphrase that can decrypt the device
    * tmpdir: (optional) a directory for temporary LUKS key files

    If modifications must be done, either existing_keyfile or existing_passphrase
    must be supplied.  If the device is already bound, neither are necessary.
    Any key material is securely written to a temporary file the system-wide
    temporary directory unless specified otherwise.
    """
    quoted_path = quote(name)
    j = {"url": url}
    qjson = quote(json.dumps(j))

    try:
        p = subprocess.run(["clevis", "luks", "list", "-d", name], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if p.returncode != 0:
            return dict(name=name, result=False, changes={}, comment=p.stdout)
    except Exception as e:
            return dict(name=name, result=False, changes={}, comment=str(e))

    bound_tang_servers = [
        json.loads(split(l.split()[-1])[0])
        for l in p.stdout.splitlines()
        if l.strip()
    ]

    if any(j == server for server in bound_tang_servers):
        return dict(name=name, result=True, changes={}, comment="Device {name} already paired with Tang server {url}")
    
    with _keyfile(existing_keyfile, existing_passphrase, tmpdir) as k:
        qexistingkeyfile = quote(k)
        return _single(
            name,
            "cmd.run",
            name=f"""
                if [ ! -f {qexistingkeyfile} ] || [ $(stat -c %s {qexistingkeyfile}) = 0 ]
                then
                    echo To enroll device {quoted_path}, an existing_keyfile or existing_passphrase is needed >&2
                    exit 16
                fi
                set -e
                set -o pipefail
                echo Enrolling device {quoted_path}. >&2
                clevis luks bind -y -k {qexistingkeyfile} -d {quoted_path} tang {qjson} >&2
                echo Enrolled device {quoted_path}. >&2
                echo
                echo changed=yes
                clevis luks list -d {quoted_path} >&2
            """,
            stateful=True,
            *args,
            **kwargs,
        )
