#!/bin/bash

set -e

cmd=
if [ "$DEBUG" != "" ] ; then
    cmd=echo
fi
check=
if [ "$1" == "check" ] ; then
    check=true
fi
force=
if [ "$1" == "force" ] ; then
    # User has requested reinstall.
    force=true
fi

which dkms >/dev/null 2>&1 || {
  echo
  echo changed=no comment="'This machine does not have DKMS.  Nothing to do.'"
  exit 0
}

created_initramfses=
changed=no
for kver in $(rpm -q kernel --queryformat="%{version}-%{release}.%{arch}\n")
do
    if [ "$check" == "true" ]
    then
        echo "=== Checking status of kernel version $kver ===" >&2
        dkms status -k "$kver" >&2
    else
        dks=$(dkms status -k "$kver" | grep zfs || true)
        if [ "$dks" == "" ] ; then
            # No ZFS for this kernel, we continue.
            continue
        fi
        echo "$dks" >&2 || true
        zfsver=$(echo "$dks" | egrep -o "(([0-9]+[.])+[0-9]+)" | head -1)
        installed=$(echo "$dks" | grep installed || true)
        if [ "$zfsver" != "" ] && [ -z "$installed" -o "$force" == "true" ]
        then
            echo "=== Rebuilding for kernel version $kver ===" >&2
            $cmd dkms uninstall -k "$kver" zfs/"$zfsver" >&2 || echo "no need to uninstall" >&2
            $cmd dkms remove -k "$kver" zfs/"$zfsver" >&2 || echo "no need to remove" >&2
            $cmd dkms install -k "$kver" zfs/"$zfsver" >&2
            if test -f /boot/initramfs-"$kver".img ; then
                $cmd cp -f /boot/initramfs-"$kver".img /boot/initramfs-"$kver".img.knowngood >&2
            fi
            $cmd dracut -f --kver "$kver" >&2
            changed=yes
        fi
        created_initramfses="$created_initramfses /boot/initramfs-$kver.img.knowngood" >&2
    fi
done

if [ "$check" != "true" ] ; then
    for initramfs in /boot/initramfs-*img.knowngood
    do
        found=false
        for created_initramfs in $created_initramfses
        do
            if [ "$initramfs" == "$created_initramfs" ]
            then
                found=true
            fi
        done
        if [ "$found" == "false" -a -f "$initramfs" ]
        then
            echo "=== Removing obsolete initial RAM disk $initramfs ===" >&2
            $cmd rm -f "$initramfs" >&2
            changed=yes
        fi
    done
fi

echo
echo changed=$changed
