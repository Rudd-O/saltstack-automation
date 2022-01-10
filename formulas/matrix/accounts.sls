#!objects


from salt://lib/qubes.sls import rw_only_or_physical


Test.nop("Accounts not yet defined")

def user(acct, config_file):
    tpl = """
set -e
set -o pipefail
ret=0
changed=false
out=$(echo | register_new_matrix_user -u %s -p %s %s -c %s 2>&1) || ret=$?
changed=true
echo "$out" >&2
if [ "$ret" != "0" ] ; then
    if echo "$out" | grep -q "User ID already taken" ; then
        ret=0
        changed=false
    fi
fi
echo
echo changed=$changed
exit $ret
    """
    return tpl % (
        salt.text.quote(u),
        salt.text.quote(p),
        "-a" if a else "",
        salt.text.quote(config_file)
    )

if rw_only_or_physical():
    accts = pillar("matrix:accounts", [])
    server_url = "https://localhost:8448"
    config_file = "/etc/synapse/homeserver.yaml"
    for acct in accts:
        u = acct['user']
        p = acct['password']
        a = acct.get('admin', False)
        Cmd.run(
            "create user %s" % u,
            name=user(acct, config_file),
            require=[Test("Accounts not yet defined")],
            require_in=[Test("Accounts defined")],
            stateful=True,
        )

Test.nop("Accounts defined")
