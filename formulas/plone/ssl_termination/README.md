# SSL termination for Plone

This formula uses NginX to terminate SSL for Plone.

It requires the following pillar:

```
plone:
  ssl_termination:
    server_name: example.org
```

Or this one:

```
plone:
  ssl_termination:
    server_names:
    - example.org
```

The `plone:ssl_termination` pillar also accepts a `backend` entry with a `host:port` specification.
This will be the proxy backend (HTTP-only) that will be contacted after SSL is terminated by NginX.
By default, it will use the standard `127.0.0.1` address and the standard Varnish port.
