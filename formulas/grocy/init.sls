#!objects

from shlex import quote
from textwrap import dedent

from salt://lib/qubes.sls import template
from salt://lib/defs.sls import SystemUser

username = "grocy"
datadir = "/var/lib/grocy"


include(f"{sls}.ssl")

deps = Pkg.installed(
    "grocy deps",
    pkgs=["grocy"],
).requisite

q = Qubes.enable_dom0_managed_service("php-fpm", require=[deps]).requisite

fpmconf = File.managed(
    "/etc/php-fpm.d/grocy.conf",
    contents=dedent(
        """\
        [grocy]
        user = apache
        group = apache
        listen = /run/php-fpm/grocy.sock
        listen.acl_users = apache,nginx
        listen.allowed_clients = 127.0.0.1
        pm = dynamic
        pm.max_children = 10
        pm.start_servers = 5
        pm.min_spare_servers = 5
        pm.max_spare_servers = 10
        slowlog = /var/log/php-fpm/nginx-slow.log
        php_admin_value[error_log] = /var/log/php-fpm/nginx-error.log
        php_admin_flag[log_errors] = on
        php_value[session.save_handler] = files
        php_value[session.save_path]    = /var/lib/php/session
        php_value[soap.wsdl_cache_dir]  = /var/lib/php/wsdlcache
        php_value[memory_limit] = 64M
        php_value[upload_max_filesize] = 50M
        php_value[post_max_size] = 50M
        php_value[output_buffering] = false
        env[PATH] = /usr/local/bin:/usr/bin:/bin
        env[TMP] = /var/tmp
        env[TMPDIR] = /var/tmp
        env[TEMP] = /var/tmp
        """
    ),
    require=deps,
).requisite

policy = Selinux.fcontext_policy_present(
    "SELinux context for Grocy directory",
    name=datadir + "(/.*)?",
    sel_type="httpd_var_lib_t",
).requisite

if not template():
    Service.running("php-fpm reloaded", name="php-fpm", watch=fpmconf, require=[q])
    settings = pillar("grocy:settings", {})

    data = File.directory(
        datadir,
        makedirs=True,
        user="apache",
        group="apache",
        mode="0770",
        require=[deps],
    ).requisite
    data_bind = Qubes.bind_dirs(
        'grocy-data',
        directories=[datadir],
        require=data,
    ).requisite
    Selinux.fcontext_policy_applied(
        "SELinux context applied on Grocy directory",
        name=datadir,
        recursive=True,
        require=[policy, data, data_bind],
    )
    config = File.managed(
        datadir + '/config.php',
        source=f"salt://{sls}/config.php.j2",
        user="apache",
        group="apache",
        mode="0440",
        require=[data_bind],
        context=settings,
        template="jinja",
    ).requisite
