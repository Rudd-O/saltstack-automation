#!/bin/bash

set -xe

curr=$(cat /.distupgrade | head -1)
next=$(cat /.distupgrade | tail -1)

stdout=$(dnf distro-sync -y --best --releasever="$next")
changed=no
if echo "$stdout" | grep -q "Nothing to do." ; then changed=yes ; fi
echo "$stdout"
echo
echo changed=$changed
