#!objects


Cmd.run(
    "Patch GRUB",
    name="set -ex; if test -x /usr/sbin/fix-grub-mkconfig ; then /usr/sbin/fix-grub-mkconfig ; fi",
)

Cmd.run(
    "Regenerate GRUB",
    name="set -ex; if test -f /boot/grub2/grub.cfg ; then /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg ; fi",
    require=[Cmd("Patch GRUB")],
)
