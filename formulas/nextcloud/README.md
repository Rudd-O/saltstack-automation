# SaltStack formula for Nextcloud on Fedora

This formula completes the initial setup of Nextcloud so that you may run the
first-run wizard on your new Nextcloud instance.  The formula uses Apache and
takes over the root of the HTTP server to directly run Nextcloud on it,
instead of as a subdirectory `/nextcloud/` on the HTTP server.

Once setup is completed, you can follow the first-run wizard and then continue
on with the [Nextcloud manual as usual](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/index.html).

## Pillar data

Here is a sample pillar data file that the formula uses to customize its
operation:

```
nextcloud:
  database:
    name: nextcloud
    user: nextcloud
    password: my nextcloud database user password goes here
  admin:
    user: admin
    password: my administrative user for Nextcloud goes here
  trusted_domains:
  # The first item in this list will be the domain to which
  # the Nextcloud instance responds to (i.e. if this was
  # machine.local, then the URL that serves Nextcloud will 
  # be http://machine.local/ ).
  # More domains are optionally possible too.
  - cloud.yourserver.com
```

### Database tuning

This formula depends on the [mariadb](../mariadb/) formula.  You can tune
your database for maximum performance like so:

```
mariadb:
  site_settings:
    mysqld:
      innodb_buffer_pool_size: 2147483648
```

Choose a size in bytes for your buffer pool size that (a) fits in RAM,
(b) does not make your machine swap (c) fits the entirety of your database,
or at least the largest tables (`ls -la /var/lib/mysql/data/nextcloud`)
in RAM.

Anything under `site_settings` will be configured under file
`/etc/my.cnf/site_settings.cnf` and will be read by the respective MySQL
or MariaDB program (`mysqld` or `mysql` for example).  Refer to the
database manual to figure out which server variables can be configured
through this mechanism.

## Known issues

* Running the OCC command to change settings, or making administrative settings
  changes in the UI, causes some settings which this formula sets up to be
  erased.  I'm working on a solution to this issue.  For now, the settings
  chunk is disabled.
