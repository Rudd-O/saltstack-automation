#!/bin/bash

set -e

which zfs >/dev/null 2>&2 || {
    echo
    echo changed=no comment="'This machine has no ZFS.'"
    exit 0
}

rootdataset=$(zfs list / -H -o name) || {
    echo
    echo changed=no comment="'This machine has no ZFS datasets.'"
    exit 0
}

sname="$rootdataset@distupgrade-from-$1-to-$2"

zfs list "$sname" -H -o name || {
    echo
    echo changed=no comment="'The snapshot $sname already exists.'"
    exit 0
}

zfs snapshot "$sname"
echo
echo changed=yes comment="'Snapshot $sname taken.'"
