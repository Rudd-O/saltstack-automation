#!/usr/bin/env python

import glob
import os
import pprint
import subprocess


def qubes():
    grains = {}
    with open(os.devnull, "w") as devnull:
        try:
            grains['vm_type'] = subprocess.check_output(['qubesdb-read', '/qubes-vm-type'], stderr=devnull, universal_newlines=True).strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            if os.path.exists("/etc/qubes-release"):
                grains['vm_type'] = "AdminVM"
        try:
            grains['persistence'] = subprocess.check_output(['qubesdb-read', '/qubes-vm-persistence'], stderr=devnull, universal_newlines=True).strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            if grains.get('vm_type') == "AdminVM":
                grains['persistence'] = "full"
        try:
            grains['updateable'] = subprocess.check_output(['qubesdb-read', '/qubes-vm-updateable'], stderr=devnull, universal_newlines=True).strip()
            grains['updateable'] = True if grains['updateable'] == "True" else False
        except (subprocess.CalledProcessError, FileNotFoundError):
            # dom0 or physical machine -- updateable
            grains['updateable'] = True
    if os.path.isdir("/run/qubes-service"):
        grains["services"] = {}
        for g in glob.glob("/run/qubes-service/*"):
            n = os.path.basename(g)
            grains["services"][n] = True
    return {'qubes': grains}


if __name__ == '__main__':
    pprint.pprint(qubes())
