#!objects

import json

from shlex import quote, split

from salt://lib/qubes.sls import Qubify, dom0, fully_persistent_or_physical, rw_only_or_physical
from salt://lib/defs.sls import Perms
from salt://prometheus/config.sls import config


context = pillar("nbde:client")

p = Pkg.installed("clevis-pkgs", pkgs=["clevis", "clevis-luks", "clevis-dracut"]).requisite
cfg = File.managed(
    "/etc/dracut.conf.d/clevis.conf",
    contents="hostonly_cmdline=yes\n",
    require=[p],
).requisite
dracut = Cmd.wait(
    "regenerate dracut",
    name="dracut -fv --regenerate-all",
    watch=[cfg],
).requisite

text = __salt__["file.read"]("/etc/crypttab")
lines = text.splitlines()

if context.get("passphrase"):
    key = [File.managed(
        "/run/luks-key present",
        name="/run/luks-key",
        mode="0400",
        contents=context.get("passphrase") + "\n",
    ).requisite]
    key_absent = [File.absent(
        "/run/luks-key absent",
        name="/run/luks-key",
        require=key,
    ).requisite]
else:
    key = []
    key_absent = []

for line in lines:
    if not line.strip() or line.startswith("#"):
        continue
    try:
        dev = line.split()[1]
    except IndexError:
        continue

    try:
        existing_passphrase = line.split()[2]
    except IndexError:
        existing_passphrase = "none"
    if existing_passphrase in ("none", "-"):
        # Crypttab says there is no passphrase
        # or there is no passphrase in crypttab
        # so we operate on this device.
        pass
    else:
        # The opposite case.
        # We will not clevis this device.
        continue

    if dev.startswith("UUID="):
        dev = "/dev/disk/by-uuid/" + dev[5:]
    else:
        dev = "/dev/" + dev

    qdev = quote(dev)
    j = {"url": context["server"]}
    qjson = quote(json.dumps(j))

    text = __salt__["cmd.run"](f"which clevis >/dev/null 2>&1 || exit 0 ; clevis luks list -d {qdev}")
    assert isinstance(text, str), text
    bound_tang_servers = [
        json.loads(split(l.split()[-1])[0])
        for l in text.splitlines()
        if l.strip()
    ]

    if not any(j == server for server in bound_tang_servers):
        Cmd.run(
            f"Pair device {dev}",   
            name="""
                test -f /run/luks-key || {
                    echo "No passphrase was set in pillar nbde:client:passphrase" >&2
                    exit 16
                }
                set -e
                set -o pipefail
                clevis luks bind -y -d %(qdev)s -k - tang %(qjson)s >&2 < /run/luks-key
                echo
                echo changed=yes
                clevis luks list -d %(qdev)s >&2
            """ % locals(),
            stateful=True,
            require=[p] + key,
            require_in=key_absent,
            watch_in=[dracut],
        )
