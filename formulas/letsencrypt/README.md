# Basic Let's Encrypt formula

Assuming your host has a public IP address and the right DNS entries point to your host,
you can create Let's Encrypt certificates (this uses NginX to do the handshake) using
the following pillar:

```
letsencrypt:
  renewal_email: toby@example.com
  hosts:
    example.org: {}
    example.com: {}
```

You can also generate self-signed certificates with the following pillar:

```
letsencrypt:
  # Or add fake here instead on each host.
  # fake: true
  hosts:
    example.org:
      fake: true
    example.com:
      fake: true
```
