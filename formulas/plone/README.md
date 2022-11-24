# Plone formula

This formula is composed of three parts:

The `ssl_termination` formula leverages the `letsencrypt` formula to create an SSL certificate
for the server name, which must be configured as a key in the `letsencrypt:hosts` pillar, and
also as pillar `plone:ssl_termination:server_name`.  It then sets up an NginX instance that
redirects all incoming HTTP traffic to HTTPS, and all HTTPS traffic to the address specified
in pillar `plone:ssl_termination:backend`.

The `container` formula sets up one or more Plone deployments with independent data folders.
These are configured as dictionaries under the `plone:container:deployments` pillar.  Each
deployment runs one ZEO instance and N Zope backends connected to that ZEO instance (see
below for `backend_processes` to alter the backend count).

The `content_cache` formula deploys Varnish.  The `director` pillars can configure how the
appropriate Plone backend is selected from the existing list of backends.

A command `reset-plone-instance` is provided which resets the data of any deployed Plone
instance based on the data of any other Plone instance (by default `master`).  The name of
the instance to reset must be provided as the first parameter, and the name of the base
instance can be provided as the second parameter.

By default, any new deployments (with an empty ZODB on which you can create a site) will
have a manager user `admin` with password `admin`.  This default comes from the upstream
Plone backend container (file `inituser` within the container).

## Sample pillar for a complete Plone formula

A machine that runs this formula could use the following pillar (listing some, non-exhaustive
settings) to set an entire Plone cluster up, with only one deployment:

```
letsencrypt:
  hosts:
    staging.example.org: {}
plone:
  ssl_termination:
    server_name: staging.example.org
    backend: 127.0.0.1:6081
  content_cache:
    listen_addr: 127.0.0.1:6081
  container:
    directories:
      datadir: /srv/plone
    users:
      process: plone
    base_port: 8080
    deployments:
      master:
        image: "plone:5.2.7"
        zeo_image: docker.io/plone/plone-zeo:latest
    director:
    - host_regex:"^staging.example.org$"
      deployment: master
      site: Plone
```

These settings would:

* Request a Let's Encrypt certificate for `staging.example.org`.
* Properly set up NginX to serve that domain over SSL.
* Deploy a Plone container image to listen on `127.0.5.1:8080`,
  ensuring that Plone runs as a non-root user, and stores
  its data under `/srv/plone/master-green`.
* Direct Varnish to listen on `127.0.0.1:6081`, to proxy requests
  to the aforementioned Plone container image, and to ensure that
  by default, requests go to site named `Plone`.  The main Plone
  admin screen would be exposed thru URL path `/deployments/master`.
* Direct NginX to connect to Varnish at `127.0.0.1:6081`.

## Settings documentation

* `plone:ssl_termination:hsts`: boolean defaulting to `True`; if
  disabled, HSTS headers are not included.

### `plone:container` pillar

Contains a dictionary with various defaults:

* `green_listen_addr_prefix` / `blue_listen_addr_prefix`, the
  first three octets of a local IP address where the blue / green
  deployments should listen (the fourth is computed based on order).
* `directories`: a set of paths that decode where the data is placed
  (only `datadir` is supported).
* `backend_processes`: default count of backend processes that
  each backend will start.

### `plone:container:deployments` pillar

This pillar contains a dictionary of `{name -> settings}` where the
supported settings are:

* `image`: defines the container image that will be used to deploy
  the Plone backend.  Images are expected to support the `LISTEN_PORT`
  variable to define on which port they will listen (this feature is
  tracked in bug https://github.com/plone/plone-backend/pull/69). By
  default this uses the latest beta 6 Plone image from `docker.io`.
* `zeo_image`: defines the container image that will be used to deploy
  ZEO.  By default this uses the stable ZEO image from `docker.io`.
* `based_on`: when dealing with new deployments, initialize the
  data for this deployment based on the named deployment.  If this
  deployment already exists, this setting is ignored.
* `delete`: if mentioned, delete all traces of the deployment.
* (there are other undocumented settings at this time)
* `backend_processes`: defines a custom backend process count
  for this deployment, overriding the default `backend_processes`
  for all deployments.

All deployments are accessible directly under URL
`https://<any server hostname>/deployments/<deployment name>`.

The first deployment listed will always be the default deployment.

See beginning of document for default manager user name and password
on freshly-created sites.


### `plone:container:backend_processes` pillar

This pillar is a number (default 2) which defines the number of backend
processes per deployment by default.  Increase this to your machine's
core count, then tune for performance and throughput.

### `plone:container:director` pillar

This pillar contains a list of `[host_regex, url_regex, site, folder]`
where the supported settings are:

* `host_regex`: defines which host names match (default all)
* `url_regex`: defines which URL path pattern matches (default all)
* `folder`: if a subfolder of the site should be served
* `deployment`: defines a deployment from the list of deployments
  that the host name will use.  If unspecified, it defaults to the
  first deployment in the deployments list.
* `site`: defines a Plone site (URL fragment from the root of the
  Plone container) to serve at this hostname.  If unspecified, it
  will simply serve the root of the Plone container.

If the client's URL or host do not match anything (because there
is no matching director entry), no Plone backend will be selected
and there will be no response to the client unless another backend
is defaulted to.

### `plone:content_cache` pillar

This pillar may contain three different key/pair values:

* `listen_addr` in host:port format to define where Varnish will
  listen to HTTP request.
* `opts` to specify which command-line options to pass to Varnish
* `purgekey` is a string that enables cache purging if specified,
  but only to clients that possess the string and pass it in the
  URL.

Plone backends are fixed to a maximum of 90 simultaneous connections
from the content cache, since beyond that `waitress` stops serving.

## Cache purging

If a `purgekey` is set (see above), then clients that call URL
`https://site.com/purgekey=<the purge key>/abc` with method `PURGE`
will get `https://site.com/abc` purged from the cache.

The general formula for the purge URL is:

* the regular base URL of your front end host name
* `/purgekey=` with the purge key added to the right,
* `/url` which can be whatever URL you want to purge.

So, if your Plone instance is running at `abc.com`, and you settled
on a purge key `zzz`, then the URL you would put in your Plone
caching settings (*Caching proxies*) would be
`https://abc.com/purgekey=zzz`.  If you run multiple domains, you
may want to configure multiple of these URLs in that setting field,
all with different domain names.

Remember: with no purge key (the default), purging is disabled.