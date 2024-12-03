#!objects

from shlex import quote

from salt://lib/qubes.sls import dom0, fully_persistent_or_physical, template


def _proxy():
    if template():
        proxy = "http://127.0.0.1:8082/"
    else:
        proxy = ""
    return proxy


def flatpak_repo():
    if fully_persistent_or_physical() and not dom0():
        p = Pkg.installed("flatpak", pkgs=["flatpak", "flatseal"]).requisite
        return Cmd.run(
            "Configure Flatpak public repository",
            name="""
changed=no
export https_proxy=""" + _proxy() + """
export http_proxy=""" + _proxy() + """
flatpak remote-list | grep -q flathub.*system || {
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >&2 || exit $?
    changed=yes
}
echo
echo changed=$changed
""",
            stateful=True,
            require=[p],
        ).requisite
    else:
        return Cmd.wait(f"echo nothing to do for {sls}").requisite


def flatpak_pkg_installed(name, **kwargs):
    if fully_persistent_or_physical() and not dom0():
        return Cmd.run(
            f"Install {name}",
            name=f"""
changed=no
export https_proxy=""" + _proxy() + f"""
export http_proxy=""" + _proxy() + f"""
if flatpak list | grep -q {quote(name)}
then
    true
else
    flatpak install -y {quote(name)} >&2 || exit $?
    echo Flatpak package installed >&2
    changed=yes
fi
if ! test -f /usr/share/applications/{quote(name)}.desktop
then
    ln -sf /var/lib/flatpak/exports/share/applications/{quote(name)}.desktop /usr/share/applications/{quote(name)}.desktop >&2 || exit $?
    echo Symlink created >&2
    changed=yes
fi
if [ "$changed" == "yes" -a -f /etc/qubes-rpc/qubes.PostInstall ]
then
    /etc/qubes-rpc/qubes.PostInstall || exit $?
    echo Application menus synced >&2
fi
echo
echo changed=$changed
""",
            stateful=True,
            require=[Cmd("Configure Flatpak public repository")],
        ).requisite
    else:
        return Test.nop(name).requisite


def flatpak_updated(name=None, require=None):
    name = name or "Update Flatpak packages"
    require = require or []
    if fully_persistent_or_physical() and not dom0():
        return Cmd.run(
            f"{name}",
            name=f"""
if ! which flatpak >/dev/null 2>&1 ; then
    echo
    echo "changed=no comment='No Flatpak apps installed on this system'"
    exit 0
fi

changed=no
export https_proxy=""" + _proxy() + f"""
export http_proxy=""" + _proxy() + f"""
ret=0 ; output=$(flatpak update -y 2>&1) || ret=$?
if [ $ret != 0 ] ; then
    echo "$output" >&2
    exit $?
fi
if echo "$output" | grep -q "Nothing to do" ; then
    changed=no
else
    changed=yes
fi
echo "$output" >&2
echo
echo changed=$changed
""",
            stateful=True,
            require=require,
        ).requisite
    else:
        return Test.nop(name).requisite


# FIXME: if appmenus aren't syncing, try
# https://dataswamp.org/~solene/2023-09-15-flatpak-on-qubesos.html#_Syncing_app_menu_script

# FIXME: convert this into Python state module.
