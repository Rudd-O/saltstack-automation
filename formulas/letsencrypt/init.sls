#!objects

from shlex import quote
from os.path import dirname

from salt://lib/qubes.sls import template, fully_persistent_or_physical
from salt://lib/letsencrypt.sls import certbot_webroot, certbot_live, certificate_dir, fullchain_path, privkey_path, renewal_hook, fake_for


# FIXME: if all requested certificates are fake, simply do not include NginX at all.

include("nginx")

if fully_persistent_or_physical():
    Pkg.installed("ca-certificates", require_in=[Pkg("certbot")])
    pk = Pkg.installed("policycoreutils").requisite
    with Pkg.installed("certbot"):
        q = Qubes.enable_dom0_managed_service("certbot-renew", enable=False).requisite
        Service.enabled("certbot-renew.timer", require=[q])
    deps = [Qubes("certbot-renew"), Service("certbot-renew.timer"), pk]
else:
    deps = []

if not template():
    context = pillar("letsencrypt", {})
    default_renewal_email = context.get("renewal_email")
    at_least_one_is_not_fake = False

    if "hosts" not in context or not context["hosts"]:

        Test.fail_without_changes(
            "the letsencrypt formula requires a dictionary of hosts under pillar letsencrypt",
            require_in=[Test("all certificates generated")],
        )

    else:

        hosts = context["hosts"]
    
        File.directory(
            dirname(certbot_webroot),
            require=deps,
            require_in=[Qubes("90-matrix-certbot")],
            makedirs=True,
        )
        with Qubes.bind_dirs(
            '90-matrix-certbot',
            directories=[dirname(certbot_webroot)],
        ):
            File.directory(
                certbot_webroot,
                require=[Qubes('90-matrix-certbot')],
                require_in=[Service("nginx running in HTTP-only mode")],
            )

        for host, data in hosts.items():
            cert = fullchain_path(host)
            key = privkey_path(host)

            if fake_for(host):
                if not (salt.file.file_exists(cert) and salt.file.file_exists(key)): # FIXME this could be replaced by cmd.run with creates=
                    C = Cmd.run
                    cmd = 'openssl req -x509 -out /tmp/%(host)s.crt -keyout /tmp/%(host)s.key -newkey rsa:2048 -nodes -sha256 -subj "/CN=%(host)s" -extensions EXT -config <( printf "[dn]\nCN=%(host)s\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:%(host)s\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth") && mkdir -p $(dirname %(cert)s) && mv /tmp/%(host)s.key %(key)s && mv /tmp/%(host)s.crt %(cert)s && restorecon $(dirname %(cert)s) %(cert)s %(key)s'
                    cmd = cmd % locals()
                else:
                    C = Cmd.wait
                    cmd = "echo Certificates are already generated"
            else:
                at_least_one_is_not_fake = True
                renewal_email = data.get("renewal_email", default_renewal_email)
                if not renewal_email:
                    raise KeyError("a renewal_email is needed by default in letsencrypt pillar or for the host")
                account_number = data.get("account_number", None)

                if not (salt.file.file_exists(cert) and salt.file.file_exists(key)): # FIXME this could be replaced by cmd.run with creates=
                    C = Cmd.run
                    quoted_renewal_email = quote(renewal_email)
                    quoted_webroot = quote(certbot_webroot)
                    quoted_host = quote(host)
                    cmd = f"certbot certonly -m {quoted_renewal_email} --agree-tos --webroot -w {quoted_webroot} -d {quoted_host}"
                    if account_number:
                        quoted_account_number = quote(str(account_number))
                        cmd = f"set -o pipefail ; echo {quoted_account_number} | " + cmd
                else:
                    C = Cmd.wait
                    cmd = "echo Certificates are already generated"
            C(
                "generate certificate for %s" % host,
                name=cmd,
                require=[Service("nginx running in HTTP-only mode")] + deps,
                watch_in=[Service("nginx")],
                require_in=[Test("all certificates generated")] + ([] if fake_for(host) else [Cmd("certbot timer running")]),
                creates=cert,
            )

    if at_least_one_is_not_fake:
        # At least one needs the timer running.
        # No onchanges parameter, so the command will run.
        kwargs = {}
    else:
        # They are all fakes.  We avoid starting the service
        # for no reason (it is enabled so it will start on
        # reboot) by enabling the onchanges empty parameter.
        kwargs = {"onchanges": []}

    Cmd.run(
        "certbot timer running",
        name="systemctl is-active certbot-renew.timer >&2 && exit 0 ; systemctl start --no-block certbot-renew.timer && echo && echo changed=yes",
        stateful=True,
        **kwargs,
    )

    Test.nop(
        "all certificates generated",
        require=[Cmd("certbot timer running")],
        require_in=[Service("nginx")],
    )

    renewal_hook("nginx")
