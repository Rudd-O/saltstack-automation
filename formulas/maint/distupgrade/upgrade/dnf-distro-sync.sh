#!/bin/bash

set -xe

curr=$(cat /.distupgrade | head -1)
next=$(cat /.distupgrade | tail -1)

changed=yes
ret=0
output=$(ionice -c 3 nice dnf distro-sync -y --best --releasever="$next" 2>&1) || ret=$?
echo "$output" >&2
if [ "$ret" != "0" ] ; then exit $ret ; fi

if echo "$output" | grep -q "Nothing to do." ; then changed=no ; fi
echo
echo changed=$changed
