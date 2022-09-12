#!/usr/bin/env python

import glob
import os
import pprint
import subprocess


def networkmanager():
    grains = {}
    for f in glob.glob("/etc/NetworkManager/system-connections/*.nmconnection"):
        n = os.path.basename(f)
        with open(f, "r") as fd:
            n = n[:-len(".nmconnection")]
            if n not in grains:
                grains[n] = {}
            text = fd.read()
            section = None
            for l in text.splitlines():
                if not l.strip():
                    continue
                if l.startswith("["):
                    section = l[1:-1]
                else:
                    key, val = l.split("=", 1)
                    if section not in grains[n]:
                        grains[n][section] = {}
                    grains[n][section][key] = val
    return {'networkmanager': grains}


if __name__ == '__main__':
    pprint.pprint(networkmanager())
