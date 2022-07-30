# SSL-encrypted Linux distribution repository / file server

This formula uses NginX to serve files over SSL.

It requires the following pillar:

```
build:
  repo:
    mirror:
      server_name: example.org
```

Or this one:

```
build:
  repo:
    mirror:
      server_names:
      - yum.example.org
      - apt.example.org
```

All the hostnames must be defined in the `letsencrypt` pillar as per the
`letsencrypt` formula documentation.

By default the repository directory that will be served is `/srv/repo`,
but you can change that by altering pillar `build:repo:mirror:root`.

HSTS is enabled by default.  The pillar `build:repo:mirror:hsts` can be
set to `False` to disable it.

Pusher clients access the `mirrorersh` program (a very simple and limited
shell) via SSH.  The authorized keys are specified via pillars:

```
build:
  repo:
    mirror:
      authorized_keys:
      - <key goes here>
```
