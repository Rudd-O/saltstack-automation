#!/usr/bin/env python

import os
import pprint
import subprocess


def qubes():
    grains = {}
    with open(os.devnull, "w") as devnull:
        try:
            grains['vm_type'] = subprocess.check_output(['qubesdb-read', '/qubes-vm-type'], stderr=devnull, universal_newlines=True).strip()
        except subprocess.CalledProcessError as e:
            if os.path.exists("/etc/qubes-release"):
                grains['vm_type'] = "AdminVM"
        try:
            grains['persistence'] = subprocess.check_output(['qubesdb-read', '/qubes-vm-persistence'], stderr=devnull, universal_newlines=True).strip()
        except subprocess.CalledProcessError:
            if grains.get('vm_type') == "AdminVM":
                grains['persistence'] = "full"
        try:
            grains['updateable'] = subprocess.check_output(['qubesdb-read', '/qubes-vm-updateable'], stderr=devnull, universal_newlines=True).strip()
            grains['updateable'] = True if grains['updateable'] == "True" else False
        except subprocess.CalledProcessError:
            if grains.get('vm_type') == "AdminVM":
                grains['updateable'] = True
    return {'qubes': grains}


if __name__ == '__main__':
    pprint.pprint(qubes())
