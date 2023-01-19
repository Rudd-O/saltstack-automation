#!/bin/bash

set -e

curr=$(cat /.distupgrade | head -1)
next=$(cat /.distupgrade | tail -1)

which zfs >/dev/null 2>&2 || {
    echo
    echo changed=no comment="'This machine has no ZFS.'"
    exit 0
}

rootdataset=$(zfs list / -H -o name) || {
    echo
    echo changed=no comment="'This machine does not have its root file system in a ZFS dataset.'"
    exit 0
}

sname="$rootdataset@distupgrade-from-$curr-to-$next"

zfs list "$sname" -H -o name && {
    echo
    echo changed=no comment="'The snapshot $sname already exists.'"
    exit 0
} || {
    zfs snapshot "$sname"
    echo
    echo changed=yes comment="'Snapshot $sname taken.'"
}
