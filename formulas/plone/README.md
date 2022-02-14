# Plone formula

This formula is composed of three parts:

The `ssl_termination` formula leverages the `letsencrypt` formula to create an SSL certificate
for the server name, which must be configured as a key in the `letsencrypt:hosts` pillar, and
also as pillar `plone:ssl_termination:server_name`.  It then sets up an NginX instance that
redirects all incoming HTTP traffic to HTTPS, and all HTTPS traffic to the address specified
in pillar `plone:ssl_termination:backend`.

The `director` formula uses Varnish to select an appropriate Plone backend from the existing
list of backends.

The `container` formula sets up one or more Plone deployments with independent data folders.
These are configured as dictionaries under the `plone:container:deployments` pillar.

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
  cache:
    listen_addr: 127.0.0.1:6081
  container:
    directories:
      datadir: /srv/plone
    users:
      process: plone
    listen_addr: 127.0.5.1
    base_port: 8080
    deployments:
      master:
        image: "plone:5.2.7"
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
