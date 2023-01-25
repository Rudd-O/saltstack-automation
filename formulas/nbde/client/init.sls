#!objects

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical, rw_only_or_physical
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

for device in __salt__["nbde.devices_from_crypttab"]().values():
    if device["keyfile"]:
        # Device uses a keyfile.
        # We will not clevis this device.
        # We will, however, test that the device is decryptable
        # using the cryptsetup-keys.d file.
        Nbde.enroll_via_keyfile(
            f'Enroll {device["path"]} via keyfile {device["keyfile"]}',
            name=device["path"],
            keyfile=device["keyfile"],
            existing_passphrase=context.get("passphrase"),
            require=[p],
            #watch_in=[dracut],
        )
    else:
        # Crypttab says there is no passphrase
        # or there is no passphrase in crypttab
        # so we operate on this device.
        Nbde.enroll_via_tang_server(
            f'Enroll {device["path"]} via server {context["server"]}',
            name=device["path"],
            url=context["server"],
            existing_passphrase=context.get("passphrase"),
            require=[p],
            #watch_in=[dracut],
        )
