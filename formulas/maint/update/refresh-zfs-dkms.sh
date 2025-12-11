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

changed=no

for a in /var/lib/dkms/zfs/*/source
do
    test -d $(dirname "$a") || continue
    if ! test -d "$a"
    then
        echo Removing "$(dirname "$a")" as it no longer points to a valid source >&2
        $cmd rm -rf "$(dirname "$a")"
        changed=yes
    fi
done

for kver in $(rpm -q kernel --queryformat="%{version}-%{release}.%{arch}\n")
do
    if [ "$check" == "true" ]
    then
        echo "=== Checking status of kernel version $kver ===" >&2
        dkms status -k "$kver" >&2
    else
        reason=
        dks=$(dkms status -k "$kver" | tail -1 | grep zfs || true) # tail to use latest DKMS ver
        if [ "$dks" == "" ] ; then
            # No ZFS for this kernel, we continue.
            continue
        fi
        echo "$dks" >&2 || true
        zfsver=$(echo "$dks" | egrep -o "(([0-9]+[.])+[0-9]+)" | head -1)
        installed=$(echo "$dks" | grep installed || true)
        if [ "$zfsver" != "" ]
        then
            if [ -z    "$installed" ] ; then reason="Not installed" ; fi
            if ! cmp /var/lib/dkms/zfs/$zfsver/$kver/$(uname -m)/module/zfs.ko.xz /usr/lib/modules/$kver/extra/zfs.ko.xz >&2
            then
                reason="Module in DKMS tree does not match module in kernel"
            fi
            if [ "$force" == "true" ] ; then reason="Force rebuild" ; fi
        fi
        if [ -n "$reason" ]
        then
            echo "-> $reason -- rebuilding for kernel version $kver ($reason)" >&2
            if [ "$DEBUG" == "" ] ; then
                echo 'post_transaction="true"' > /etc/dkms/framework.conf.d/distupgrade.conf
                trap 'rm -f /etc/dkms/framework.conf.d/distupgrade.conf' EXIT
            fi
            $cmd dkms uninstall -k "$kver" zfs/"$zfsver" >&2 || echo "no need to uninstall" >&2
            $cmd dkms remove -k "$kver" zfs/"$zfsver" >&2 || echo "no need to remove" >&2
            $cmd dkms install -k "$kver" zfs/"$zfsver" >&2
            if [ "$DEBUG" == "" ] ; then
                rm -f /etc/dkms/framework.conf.d/distupgrade.conf
            fi
            $cmd dracut -f --kver "$kver" >&2
            if test -f /boot/initramfs-"$kver".img ; then
                if test -f /boot/efi/EFI/*/initramfs-"$kver".img ; then
                    $cmd cp -f /boot/initramfs-"$kver".img /boot/efi/EFI/*/initramfs-"$kver".img >&2
                fi
            fi
            changed=yes
        else
            echo "-> No reason to rebuild for kernel version $kver" >&2
        fi
    fi
done

echo
echo changed=$changed
