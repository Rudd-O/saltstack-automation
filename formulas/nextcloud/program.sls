#!objects

from shlex import quote

from salt://lib/qubes.sls import template, fully_persistent_or_physical


if fully_persistent_or_physical():
    with Pkg.installed("nextcloud", pkgs=["nextcloud", "libreoffice-core"]):
        q1 = Qubes.enable_dom0_managed_service("httpd.socket", qubes_service_name="httpd").requisite
        q2 = Qubes.enable_dom0_managed_service("nextcloud-cron.timer", qubes_service_name="nextcloud-cron").requisite
    deps = [q1, q2]
else:
    deps = []

if not template():
    context = pillar("nextcloud", {})
    t = Test.nop("Nextcloud setup", require=deps).requisite
    h = File.managed(
        "/etc/httpd/conf.d/z-nextcloud-access.conf",
        contents="""
# If symlinked or copied to /etc/httpd/conf.d/z-nextcloud-access.conf
# (or any other name that is alphabetically later than
# 'nextcloud.conf'), this file will permit access to the ownCloud
# installation from any client. Ensure your deployment is correctly
# configured and secured before doing this!
#
# If you SYMLINK this file, you can rely on the ownCloud package to
# handle any future changes in the directory or URL hierarchy; this
# file will always achieve the high-level goal 'allow access to the
# ownCloud installation from any client'. If you COPY this file, you
# will have to check for changes to the original in future ownCloud
# package updates, and make any appropriate adjustments to your copy.

Alias /apps-appstore /var/lib/nextcloud/apps
Alias /assets /var/lib/nextcloud/assets
Alias / /usr/share/nextcloud/

<Directory /usr/share/nextcloud/>
    Include conf.d/nextcloud-auth-any.inc
    Include conf.d/nextcloud-defaults.inc
    <FilesMatch \.(php|phar)$>
        SetHandler "proxy:unix:/run/php-fpm/nextcloud.sock|fcgi://localhost"
    </FilesMatch>
    <FilesMatch ^(\.|autotest|occ|issue|indie|db_|console).*>
        Include conf.d/nextcloud-auth-none.inc
    </FilesMatch>
    ErrorDocument 403 /
    ErrorDocument 404 /
    <IfModule mod_rewrite.c>
        Options -MultiViews
        RewriteRule ^core/js/oc.js$ index.php [PT,E=PATH_INFO:$1]
        RewriteRule ^core/preview.png$ index.php [PT,E=PATH_INFO:$1]
        RewriteCond %{REQUEST_FILENAME} !\.(css|js|svg|gif|png|html|ttf|woff2?|ico|jpg|jpeg|map|webm|mp4|mp3|ogg|wav|wasm|tflite)$
        RewriteCond %{REQUEST_FILENAME} !/info\.php
        RewriteCond %{REQUEST_FILENAME} !/core/ajax/update\.php
        RewriteCond %{REQUEST_FILENAME} !/core/img/(favicon\.ico|manifest\.json)$
        RewriteCond %{REQUEST_FILENAME} !/(cron|public|remote|status)\.php
        RewriteCond %{REQUEST_FILENAME} !/ocs/v(1|2)\.php
        RewriteCond %{REQUEST_FILENAME} !/robots\.txt
        RewriteCond %{REQUEST_FILENAME} !/(ocm-provider|ocs-provider|updater)/
        RewriteCond %{REQUEST_URI} !^/\.well-known/(acme-challenge|pki-validation)/.*
        RewriteCond %{REQUEST_FILENAME} !/richdocumentscode(_arm64)?/proxy.php$
        RewriteRule . index.php [PT,E=PATH_INFO:$1]
        RewriteBase /
        <IfModule mod_env.c>
            SetEnv front_controller_active true
            <IfModule mod_dir.c>
                DirectorySlash off
            </IfModule>
        </IfModule>
    </IfModule>
</Directory>

<Directory /var/lib/nextcloud/apps/>
    Include conf.d/nextcloud-auth-any.inc
    Include conf.d/nextcloud-defaults.inc
</Directory>

<Directory /var/lib/nextcloud/assets/>
    Include conf.d/nextcloud-auth-any.inc
    Include conf.d/nextcloud-defaults.inc
</Directory>
""".lstrip(),
        require=[t],
    ).requisite
    b = Qubes.bind_dirs(
        '90-nextcloud',
        directories=['/var/lib/nextcloud', "/etc/httpd/conf.d/z-nextcloud-access.conf", "/etc/nextcloud"],
        require=deps + [h],
    ).requisite
    s = Service.running(
        "httpd",
        watch=[h],
        require=[b],
    ).requisite
    qdbname = quote(context["database"]["name"])
    qdbuser = quote(context["database"]["user"])
    qdbpassword = quote(context["database"]["password"])
    qadminuser = quote(context["admin"]["user"])
    qadminpassword = quote(context["admin"]["password"])
    setup = Cmd.run(
        "Setup nextcloud",
        name=f"set -e ; php occ maintenance:install --data-dir /var/lib/nextcloud/data/ --database mysql --database-name {qdbname} --database-user {qdbuser} --database-pass {qdbpassword} --admin-user {qadminuser} --admin-pass {qadminpassword} ; touch /var/lib/nextcloud/.setup",
        runas="apache",
        cwd="/usr/share/nextcloud",
        creates="/var/lib/nextcloud/.setup",
        require=[s],
    ).requisite

    arr = ", ".join(f"{n} => '{td}'" for n, td in enumerate(context["trusted_domains"]))
    r1 = File.replace(
        "trusted_domains setting",
        name="/etc/nextcloud/config.php",
        pattern=".CONFIG[[].trusted_domains.[]].*",
        repl=f"$CONFIG['trusted_domains'] = array({arr});",
        append_if_not_found=True,
        require=[setup],
    ).requisite
    primarydomain = context["trusted_domains"][0]
    r2 = File.replace(
        "overwrite.cli.url setting",
        name="/etc/nextcloud/config.php",
        pattern=".CONFIG[[].overwrite.cli.url.[]].*",
        repl=f"$CONFIG['overwrite.cli.url'] = 'http://{primarydomain}';",
        append_if_not_found=True,
        require=[r1],
    ).requisite
    r3 = File.replace(
        "rewritebase setting",
        name="/etc/nextcloud/config.php",
        pattern=".CONFIG[[].htaccess.RewriteBase.[]].*",
        repl=f"$CONFIG['htaccess.RewriteBase'] = '/';",
        append_if_not_found=True,
        require=[r2],
    ).requisite
