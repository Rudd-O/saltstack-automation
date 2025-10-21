#!objects

from shlex import quote
from textwrap import dedent

from salt://lib/qubes.sls import template, fully_persistent_or_physical
from salt://lib/copr.sls import copr

TMPDIR = "/var/tmp/nextcloud"
MEM = "4G"
memories_index_arguments = "-g Parents"
preview_generator_arguments = "Rudd-O Lidia"

def occ(cmd):
    return f"nice -n 20 /usr/bin/php -d sys_temp_dir={TMPDIR} -d upload_temp_dir={TMPDIR} -d memory_limit={MEM} -f /usr/share/nextcloud/occ {cmd}"

def timer_driven_unit(name, description, command, onbootsec, onunitinactivesec, require=None, watch=None, type=None):
    if fully_persistent_or_physical():
        s = File.managed(
            f"Create {name} service",
            name=f"/etc/systemd/system/{name}.service",
            contents=dedent(f"""\
            [Unit]
            Description={description}

            [Service]
            # https://docs.nextcloud.com/server/25/admin_manual/configuration_server/background_jobs_configuration.html#systemd
            Type={type if type else "oneshot"}
            User=apache
            KillMode=process
            ExecStart={command}
            """),
            require=require,
        ).requisite
        t = File.managed(
            f"Create {name} timer",
            name=f"/etc/systemd/system/{name}.timer",
            contents=dedent(f"""\
            [Unit]
            Description=This triggers {description}

            [Timer]
            OnBootSec={onbootsec}
            OnUnitInactiveSec={onunitinactivesec}

            [Install]
            WantedBy=timers.target
            """),
            require=[s],
        ).requisite
        q = Qubes.enable_dom0_managed_service(f"{name}.timer", qubes_service_name="nextcloud-cron", require=[t]).requisite
    else:
        s = Test.nop(f"Create {name} service", require=require).requisite
        t = Test.nop(f"Create {name} timer", require=[s]).requisite
        q = Test.nop(f"Enable {name} timer", require=[t]).requisite
    if not template():
        r = Service.running(
            f"Dispatch {name} timer",
            name=f"{name}.timer",
            require=[q],
            watch=[s, t] + (watch if watch else []),
        ).requisite
    else:
        r = Test.nop(
            f"Dispatch {name} timer",
            require=[q],
            watch=[s, t] + (watch if watch else []),
        ).requisite
    return (s, t, q, r)

def service_driven_unit(name, description, command, after, wantedby, require=None, watch=None, type=None, start_manually=True):
    if fully_persistent_or_physical():
        s = File.managed(
            f"Create {name} service",
            name=f"/etc/systemd/system/{name}.service",
            contents=dedent(f"""\
            [Unit]
            Description={description}
            After={after}

            [Service]
            # https://docs.nextcloud.com/server/25/admin_manual/configuration_server/background_jobs_configuration.html#systemd
            Type={type if type else "oneshot"}
            User=apache
            KillMode=process
            ExecStart={command}

            [Install]
            WantedBy={wantedby}
            """),
            require=require,
        ).requisite
        q = Qubes.enable_dom0_managed_service(f"{name}.service", qubes_service_name="nextcloud-cron", require=[s]).requisite
    else:
        s = Test.nop(f"Create {name} service", require=require).requisite
        q = Test.nop(f"Enable {name} service", require=[s]).requisite
    if not start_manually:
        r = Test.nop(f"Do not dispatch {name} service", require=[q]).requisite
    else:
        if not template():
            r = Service.running(
                f"Dispatch {name} service",
                name=name,
                require=[q],
                watch=[s] + (watch if watch else []),
            ).requisite
        else:
            r = Test.nop(
                f"Dispatch {name} service",
                require=[q],
                watch=[s] + (watch if watch else []),
            ).requisite
    return (s, q, r)


if fully_persistent_or_physical():
    include("rpmfusion")
    ffmpeg = Pkg.installed("ffmpeg", require=[Test("RPMFusion setup")]).requisite
    c = copr("matias", "dlib")
    pdlib = Pkg.installed("pdlib", require=[c]).requisite
    nextcloud = Pkg.installed("nextcloud", pkgs=["nextcloud", "libreoffice-core"], require=[ffmpeg, pdlib]).requisite
    tmpfilesd = File.managed(
        "/etc/tmpfiles.d/nextcloud.conf",
        contents=dedent(f"""\
        d {TMPDIR} 0770 apache apache 3d
        """),
        require=[nextcloud],
    ).requisite
    cronqubified = Qubes.enable_dom0_managed_service(f"nextcloud-cron.timer", qubes_service_name="nextcloud-cron", require=[nextcloud]).requisite
    cron = File.managed(
        "Up limits of nextcloud-cron.service",
        name="/etc/systemd/system/nextcloud-cron.service.d/limits.conf",
        contents=dedent(f"""\
        [Service]
        ExecStart=
        ExecStart=/usr/bin/php -d sys_temp_dir={TMPDIR} -d upload_temp_dir={TMPDIR} -d memory_limit={MEM} -f /usr/share/nextcloud/cron.php
        """),
        require=cronqubified,
        makedirs=True,
    ).requisite
    fastercron = File.managed(
        "More frequent nextcloud-cron.service",
        name="/etc/systemd/system/nextcloud-cron.timer.d/faster.conf",
        contents=dedent(f"""\
        [Timer]
        OnUnitInactiveSec=
        OnBootSec=3min
        OnUnitInactiveSec=5min
        """),
        require=cronqubified,
        makedirs=True,
    ).requisite
    fpmsettings = File.managed(
        "/etc/systemd/system/php-fpm.service.d/noprivatetmp.conf",
        makedirs=True,
        contents=dedent(f"""\
        [Service]
        PrivateTmp=false
        """),
        require=[nextcloud],
    ).requisite
else:
    nextcloud = Test.nop("nextcloud").requisite
    fpmsettings = Test.nop("/etc/systemd/system/php-fpm.service.d/noprivatetmp.conf", require=[nextcloud]).requisite
    tmpfilesd = Test.nop("/etc/tmpfiles.d/nextcloud.conf", require=[nextcloud]).requisite
    cron = Test.nop("Up limits of nextcloud-cron.service", require=[nextcloud]).requisite
    fastercron = Test.nop("More frequent nextcloud-cron.service", require=[nextcloud]).requisite
    cronqubified = Test.nop("Qubification of nextcloud-cron.timer", require=[nextcloud]).requisite

external_notify_s, external_notify_q, external_notify_r = service_driven_unit(
    "nextcloud-external-notify",
    "Nextcloud external storage notifications",
    f"""/usr/bin/bash -c 'for a in $(/usr/share/nextcloud/occ files_external:list --all | grep -E "^[|] [0-9]+.*SMB/CIFS" | cut -d " " -f 2) ; do {occ('files_external:notify')} $a & sleep 0.5 ; done ; wait'""",
    "php-fpm.service",
    "php-fpm.service",
    require=[nextcloud, tmpfilesd, fpmsettings, cronqubified, fastercron, cron],
    type="exec",
)
scan_s, scan_t, scan_q, scan_r = timer_driven_unit(
    "nextcloud-external-scan",
    "Nextcloud outdated file scan",
    occ("files:scan --all --unscanned"),
    "2min",
    "5min",
    require=[nextcloud, tmpfilesd, fpmsettings, cronqubified, fastercron, cron],
    type="oneshot",
)
scanf_s, scanf_t, scanf_q, scanf_r = timer_driven_unit(
    "nextcloud-external-scan-full",
    "Nextcloud outdated file full scan",
    occ("files:scan --all"),
    "2hr",
    "6hr",
    require=[nextcloud, tmpfilesd, fpmsettings, cronqubified, fastercron, cron],
    type="oneshot",
)
appdata_s, appdata_t, appdata_q, appdata_r = timer_driven_unit(
    "nextcloud-scan-app-data",
    "Nextcloud scan app data",
    occ("files:scan-app-data"),
    "13hr",
    "24hr",
    require=[nextcloud, tmpfilesd, fpmsettings, cronqubified, fastercron, cron],
    type="oneshot",
)
cleanup_s, cleanup_t, cleanup_q, cleanup_r = timer_driven_unit(
    "nextcloud-cleanup",
    "Nextcloud cleanup",
    occ("files:cleanup"),
    "2day",
    "7day",
    require=[nextcloud, tmpfilesd, fpmsettings, cronqubified, fastercron, cron],
    type="oneshot",
)
noscan = File.absent(
    "/etc/systemd/system/nextcloud-external-scan.service.wants/nextcloud-memories-index.service",
    require=scanf_s,
).requisite
memories_index_s, memories_index_q, memories_index_r = service_driven_unit(
    "nextcloud-memories-index",
    "Nextcloud indexing for Memories app",
    occ(f"memories:index {memories_index_arguments}"),
    "nextcloud-external-scan-full.service",
    "nextcloud-external-scan-full.service",
    start_manually=False,
    require=[scanf_s, noscan],
    type="exec",
)
generate_previews_s, generate_previews_q, generate_previews_r = service_driven_unit(
    "nextcloud-generate-previews",
    "Nextcloud preview generation",
    occ("preview:pre-generate"),
    "nextcloud-external-scan.service",
    "nextcloud-external-scan.service",
    start_manually=False,
    require=[nextcloud, tmpfilesd, fpmsettings, cronqubified, fastercron, cron],
    type="exec",
)
facerecognition_s, facerecognition_t, facerecognition_q, facerecognition_r = timer_driven_unit(
    "nextcloud-face-background-job",
    "Nextcloud facerecognition background job",
    occ("face:background_job -t 550"),
    "10min",
    "10min",
    require=[nextcloud, tmpfilesd, fpmsettings, cronqubified, fastercron, cron],
    type="exec",
)

_o = [scan_s, scan_t, scanf_s, scanf_t, noscan, appdata_s, appdata_t, cleanup_s, cleanup_t, memories_index_s, generate_previews_s, facerecognition_s, facerecognition_t, external_notify_s]
_q = [scan_q, scanf_q, appdata_q, cleanup_q, memories_index_q, generate_previews_q, facerecognition_q, external_notify_q]
_s = [scan_r, scanf_r, appdata_r, cleanup_r, memories_index_r, generate_previews_r, facerecognition_r, external_notify_r]
reload_ = Cmd.run(
    f"reload systemd for {sls}",
    name="systemctl --system daemon-reload",
    onchanges=_o + [cron],
    require_in=_q + _s,
).requisite


before_selinux = Test.nop("Before SELinux", require=[nextcloud]).requisite
after_selinux = Test.nop("After SELinux").requisite

if grains("selinux:enabled"):
    Selinux.boolean(
        "httpd_can_network_connect for Nextcloud",
        name="httpd_can_network_connect",
        value=True,
        persist=True,
        require=[before_selinux],
        require_in=[after_selinux],
    )
    Selinux.boolean(
        "httpd_use_cifs for Nextcloud",
        name="httpd_use_cifs",
        value=True,
        persist=True,
        require=[before_selinux],
        require_in=[after_selinux],
    )
    Customselinux.policy_module_present(
        "nextcloud-fixes",
        contents="""
module nextcloud-fixes 1.0;

require {
	type httpd_t;
	type initrc_t;
	class key read;
	type unconfined_service_t;
	class sem { read write unix_read unix_write associate };
}

allow httpd_t initrc_t:key read;
allow httpd_t unconfined_service_t:sem { read write unix_read unix_write associate};
""".strip(),
        require=[before_selinux],
        require_in=[after_selinux],
    ).requisite


if not template():
    context = pillar("nextcloud", {})
    t = Test.nop("Nextcloud begin setup", require=[nextcloud, after_selinux]).requisite
    h = File.managed(
        "/etc/httpd/conf.d/z-nextcloud-access.conf",
        contents=r"""
# DO NOT EDIT THIS FILE DIRECTLY. To override any element of the
# packaged ownCloud configuration, create a new /etc/httpd/conf.d/
# file which will be read later than 'nextcloud.conf'.
#
# As the initial setup wizard is active upon installation, access is
# initially allowed only from localhost. *AFTER* configuring the
# installation correctly and creating the admin account, to allow
# access from any host, do this:
#
# ln -s /etc/httpd/conf.d/nextcloud-access.conf.avail /etc/httpd/conf.d/z-nextcloud-access.conf
#
# The above has been taken care of by the includes at the bottom of this file.

Alias /apps-appstore /var/lib/nextcloud/apps
Alias /assets /var/lib/nextcloud/assets
Alias / /usr/share/nextcloud/

# Allows compliant CalDAV / CardDAV clients to be configured using only
# the domain name. For more details see # http://tools.ietf.org/html/rfc6764

# Nextcloud 29 checks specifically for trailing slash in dav 301 redirects
# https://github.com/nextcloud/server/issues/45033#issuecomment-2079306503

Redirect 301 /.well-known/carddav    /remote.php/dav/
Redirect 301 /.well-known/caldav     /remote.php/dav/
Redirect 301 /.well-known/webdav     /remote.php/dav/
Redirect 301 /.well-known/webfinger  /index.php/.well-known/webfinger
Redirect 301 /.well-known/nodeinfo   /index.php/.well-known/nodeinfo

# LogLevel alert rewrite:trace3

<Directory /usr/share/nextcloud/>
    LogLevel info
    LimitRequestBody 0
    # LogLevel info proxy_fcgi:debug
    # The following was inserted to prevent bots from accessing
    # nonsense which then generates spam logs.
    <IfModule mod_rewrite.c>
        RewriteRule sitemap.xml$ - [R=404,L]
        RewriteRule cgi-bin.* - [R=404,L]
        RewriteRule \.git.* - [R=404,L]
        RewriteRule \.env.* - [R=404,L]
        RewriteRule abc\.png$ - [R=404,L]
        # If the profiler is enabled, this rule must be deleted.
        RewriteRule _profiler.* - [R=404,L]
    </IfModule>

    Include conf.d/nextcloud-auth-any.inc
    Include conf.d/nextcloud-defaults.inc
    <FilesMatch ^(\.|autotest|occ|issue|indie|db_|console).*>
        Include conf.d/nextcloud-auth-none.inc
    </FilesMatch>
    <FilesMatch \.(php|phar)$>
        SetHandler "proxy:unix:/run/php-fpm/nextcloud.sock|fcgi://localhost"
    </FilesMatch>

    # The following was generated by creating a temp /usr/share/nextcloud/.htaccess,
    # running /usr/share/nextcloud/occ maintenance:update:htaccess , then deleting
    # the file after copying the output code to here below.
    # This applies to /usr/share/nextcloud, of course.
    ErrorDocument 403 /index.php/error/403
    ErrorDocument 404 /index.php/error/404
    # echo '<?php phpinfo() ?>' > /usr/share/nextcloud/info.php
    #    RewriteCond %{REQUEST_FILENAME} !/info\.php
    <IfModule mod_rewrite.c>
        Options -MultiViews
        RewriteRule ^core/js/oc.js$ index.php [PT,E=PATH_INFO:$1]
        RewriteRule ^core/preview.png$ index.php [PT,E=PATH_INFO:$1]
        RewriteCond %{REQUEST_FILENAME} !\.(css|js|mjs|svg|gif|ico|jpg|jpeg|png|webp|html|otf|ttf|woff2?|map|webm|mp4|mp3|ogg|wav|flac|wasm|tflite|mkv)$
        RewriteCond %{REQUEST_FILENAME} !/core/ajax/update\.php
        RewriteCond %{REQUEST_FILENAME} !/core/img/(favicon\.ico|manifest\.json)$
        RewriteCond %{REQUEST_FILENAME} !/(cron|public|remote|status)\.php
        RewriteCond %{REQUEST_FILENAME} !/ocs/v(1|2)\.php
        RewriteCond %{REQUEST_FILENAME} !/robots\.txt
        RewriteCond %{REQUEST_FILENAME} !/(ocs-provider|updater)/
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

# For safety, explicitly deny any access to these locations.
# Upstream's .htaccess does something similar with mod_rewrite.

<Directory /var/lib/nextcloud/data/>
    Include conf.d/nextcloud-auth-none.inc
</Directory>

<DirectoryMatch /usr/share/nextcloud/(3rdparty|lib|config|templates)/>
    Include conf.d/nextcloud-auth-none.inc
</DirectoryMatch>
""".lstrip(),
        require=[t],
    ).requisite
    context["temp_directory"] = context.get("temp_directory", TMPDIR)
    context["memory_limit"] = context.get("memory_limit", MEM)
    tmpdir = File.directory(
        TMPDIR,
        user="apache",
        group="apache",
        mode="0770",
        require=[t, tmpfilesd],
        selinux={
            "type": "tmp_t",
        },
    ).requisite
    tmpdir_bind = Qubes.bind_dirs(
        '90-nextcloud-tmp',
        directories=[TMPDIR],
        require=[tmpdir],
    ).requisite
    phpsettings = File.managed(
        "/etc/php-fpm.d/nextcloud-custom.conf",
        contents="""[nextcloud]
php_admin_value[memory_limit] = {{ memory_limit }}
php_admin_value[opcache.jit] = 1255
php_admin_value[opcache.jit_buffer_size] = 8M
php_admin_value[opcache.interned_strings_buffer] = 64
php_admin_value[upload_max_filesize] = {{ max_upload_size | default("50M") }}
php_admin_value[post_max_size] = {{ max_upload_size | default("50M") }}
php_admin_value[sys_temp_dir] = {{ temp_directory }}
php_admin_value[upload_temp_dir] = {{ temp_directory }}
php_admin_value[max_execution_time] = 150
""",
        template="jinja",
        context=context,
        require=[tmpdir_bind],
    ).requisite
    phpsettings_binddir = Qubes.bind_dirs(
        '90-nextcloud-php-fpm',
        directories=["/etc/php-fpm.d/nextcloud-custom.conf"],
        require=[phpsettings],
    ).requisite
    nextcloud_binddirs = Qubes.bind_dirs(
        '90-nextcloud',
        directories=['/var/lib/nextcloud', "/etc/httpd/conf.d/z-nextcloud-access.conf", "/etc/nextcloud"],
        require=[phpsettings, h],
    ).requisite
    cachedir = File.directory(
        "/usr/share/httpd/.cache",
        user="apache",
        group="apache",
        mode="0000", # FIXME once we determine disabling this cache makes preview generation responsive and not hang, then undo this shit.
        require=[nextcloud],
        require_in=[scan_q, scanf_q, appdata_q, cleanup_q],
    ).requisite
    cachebind = Qubes.bind_dirs(
        '90-nextcloud-smbcache',
        directories=['/usr/share/httpd/.cache'],
        require=[cachedir],
    ).requisite
    s1 = Service.running(
        "httpd",
        watch=[h],
        require=[nextcloud_binddirs],
    ).requisite
    s2 = Service.running(
        "php-fpm",
        watch=[phpsettings],
        require=[phpsettings_binddir, fpmsettings],
        require_in=[s1],
    ).requisite
    qdbname = quote(context["database"]["name"])
    qdbuser = quote(context["database"]["user"])
    qdbpassword = quote(context["database"]["password"])
    qadminuser = quote(context["admin"]["user"])
    qadminpassword = quote(context["admin"]["password"])
    setup_cmd = occ(f"occ maintenance:install --data-dir /var/lib/nextcloud/data/ --database mysql --database-name {qdbname} --database-user {qdbuser} --database-pass {qdbpassword} --admin-user {qadminuser} --admin-pass {qadminpassword}")
    setup = Cmd.run(
        "Setup nextcloud",
        name=f"set -e ; php {setup_cmd} ; touch /var/lib/nextcloud/.setup",
        runas="apache",
        cwd="/usr/share/nextcloud",
        creates="/var/lib/nextcloud/.setup",
        require=[s1, s2],
    ).requisite

    if 0:
        arr = ", ".join(f"{n} => '{td}'" for n, td in enumerate(context["trusted_domains"]))
        r1 = File.replace(
            "trusted_domains setting",
            name="/etc/nextcloud/config.php",
            pattern=".CONFIG[[].trusted_domains.[]].*",
            repl=f"$CONFIG['trusted_domains'] = array({arr});",
            append_if_not_found=True,
            require=[setup, logsbind],
        ).requisite
        arr = ", ".join(f"{n} => '{td}'" for n, td in enumerate(context["trusted_proxies"]))
        r2 = File.replace(
            "trusted_proxies setting",
            name="/etc/nextcloud/config.php",
            pattern=".CONFIG[[].trusted_proxies.[]].*",
            repl=f"$CONFIG['trusted_proxies'] = array({arr});",
            append_if_not_found=True,
            require=[r1],
        ).requisite
        primarydomain = context["trusted_domains"][0]
        r3 = File.replace(
            "overwrite.cli.url setting",
            name="/etc/nextcloud/config.php",
            pattern=".CONFIG[[].overwrite.cli.url.[]].*",
            repl=f"$CONFIG['overwrite.cli.url'] = 'http://{primarydomain}';",
            append_if_not_found=True,
            require=[r2],
        ).requisite
        r4 = File.replace(
            "rewritebase setting",
            name="/etc/nextcloud/config.php",
            pattern=".CONFIG[[].htaccess.RewriteBase.[]].*",
            repl=f"$CONFIG['htaccess.RewriteBase'] = '/';",
            append_if_not_found=True,
            require=[r3],
        ).requisite
        # not currently managed:
        # * log_level
        # * enabledPreviewProviders (not in pillar either)
        # * default_phone_region
        # * maintenance_window_start
        # hardcoded:
        #  'log_type' => 'file',
        #  'log_type_audit' => 'file',
        # not currently managed:
        #   occ config:app:set dav calendarSubscriptionRefreshRate --value PT2H
        # occ maintenance:mimetype:update-db
        # occ maintenance:mimetype:update-js

    # FIXME make the config tasks above be required here.
    post_setup_config = Test.nop("Post-setup configuration", require=[setup, cachebind], require_in=_q).requisite

    # https://github.com/nextcloud/previewgenerator
    preview_install = occ("app:install previewgenerator")
    preview_config = "; ".join(occ(xxx) for xxx in [
        'config:app:set --value="64 256" previewgenerator squareSizes',
        'config:app:set --value="256 4096" previewgenerator squareUncroppedSizes',
        'config:app:set --value="" previewgenerator widthSizes',
        'config:app:set --value="" previewgenerator heightSizes',
    ])
    preview_generate = occ(f"preview:generate-all {preview_generator_arguments}")
    setuppreview = Cmd.run(
        "Setup previewgenerator",
        name=f"set -e ; test -d /var/lib/nextcloud/apps/previewgenerator || {preview_install} ; {preview_config} ; {preview_generate} ; touch /var/lib/nextcloud/.preview-setup",
        runas="apache",
        cwd="/usr/share/nextcloud",
        creates="/var/lib/nextcloud/.preview-setup",
        require=[post_setup_config],
        require_in=[generate_previews_q],
    ).requisite

    # https://docs.nextcloud.com/server/latest/admin_manual/ai/app_recognize.html
    recognize_install = occ("app:install recognize")
    recognize_models = occ("recognize:download-models")
    recognize_clear = occ("recognize:clear-background-jobs")
    recognize_classify = occ("recognize:classify")
    # recognize_cluster_faces = occ("occ occ recognize:cluster-faces")
    setuprecognize = Cmd.run(
        "Setup recognize",
        name=f"set -e ; test -d /var/lib/nextcloud/apps/recognize || {recognize_install} ; {recognize_models} ; {recognize_clear} ; {recognize_classify} ; touch /var/lib/nextcloud/.recognize-setup",
        runas="apache",
        cwd="/usr/share/nextcloud",
        creates="/var/lib/nextcloud/.recognize-setup",
        require=[setuppreview],
        require_in=_q,
    ).requisite

    # https://github.com/matiasdelellis/facerecognition
    # FIXME: still missing here: face:sync-albums
    face_install = occ("app:install facerecognition")
    face_memory = occ("face:setup -M 1G")
    face_model = occ("face:setup -m 1")
    face_config = "; ".join(occ(xxx) for xxx in [
        'config:app:set facerecognition handle_external_files --value=true',
        'config:app:set facerecognition clustering_batch_size --value=5000',
    ])
    setupface = Cmd.run(
        "Setup facerecognition",
        name=f"set -e ; test -d /var/lib/nextcloud/apps/facerecognition || {face_install} ; {face_memory} ; {face_model} ; {face_config} ; touch /var/lib/nextcloud/.face-setup",
        runas="apache",
        cwd="/usr/share/nextcloud",
        creates="/var/lib/nextcloud/.face-setup",
        require=[setuprecognize],
        require_in=[facerecognition_q],
    ).requisite

    memories_install = occ("app:install memories")
    memories_places_setup = occ("memories:places-setup")
    memories_index = occ(f"memories:index {memories_index_arguments}")
    setupmemories = Cmd.run(
        "Setup memories",
        name=f"set -e ; test -d /var/lib/nextcloud/apps/memories || {memories_install} ; {memories_places_setup} ; {memories_index} ; touch /var/lib/nextcloud/.memories-setup",
        runas="apache",
        cwd="/usr/share/nextcloud",
        creates="/var/lib/nextcloud/.memories-setup",
        require=[setupface, setuppreview],
        require_in=[memories_index_q],
    ).requisite
