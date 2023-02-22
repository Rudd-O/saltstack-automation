#!objects

from shlex import quote

from salt://maint/config.sls import config


dep = Test.nop("After enabling units").requisite
predep = Test.nop("Before enabling units").requisite

for unit in config.distupgrade.get("units_to_stop", []):
    qunit = quote(unit)
    Cmd.run(
        "Enable unit %s" % unit,
        name=f"""
systemctl status {qunit} >&2
if [ "$ret" == "4" ] ; then exit 0 ; fi # does not exist
if [ "$ret" == "0" ] ; then exit 0 ; fi # already running
systemctl start {qunit} >&2
echo changed=yes
""",
        stateful=True,
        require=[predep],
        require_in=[dep],
    )
