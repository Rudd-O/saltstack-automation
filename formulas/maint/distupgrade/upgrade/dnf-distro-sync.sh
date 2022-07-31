#!/bin/bash

set -xe

stdout=$(dnf distro-sync -y --best --releasever="$1")
changed=no
if echo "$stdout" | grep -q "Nothing to do." ; then changed=yes ; fi
echo "$stdout"
echo
echo changed=$changed
