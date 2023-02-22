#!objects

from shlex import quote

from salt://maint/config.sls import config


dep = Test.nop("Before disabling units").requisite
postdep = Test.nop("After disabling units").requisite

for unit in config.distupgrade.get("units_to_stop", []):
    qunit = quote(unit)
    Cmd.run(
        "Disable unit %s" % unit,
        name="""
systemctl status {qunit} >&2
if [ "$ret" == "4" ] ; then exit 0 ; fi # does not exist
if [ "$ret" == "0" ] ; then # active
    systemctl stop {qunit} >&2
    echo changed=yes
fi
""",
        stateful=True,
        require=[dep],
        require_in=[postdep],
    )
