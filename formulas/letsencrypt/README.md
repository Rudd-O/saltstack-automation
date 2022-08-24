# Basic Let's Encrypt formula

Assuming your host has a public IP address and the right DNS entries point to your host,
you can create Let's Encrypt certificates (this uses NginX to do the handshake) using
the following pillar:

```
letsencrypt:
  renewal_email: toby@example.com
  hosts:
    example.org: {}
    www.example.org: {}
    example.com: {}
    www.example.com: {}
```

Note that requesting a certificate for `x.com` will not give you a certificate
valid both for `x.com` and `www.x.com`.  You have to list them separately.

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

When your host has multiple accounts, Let's Encrypt's `certbot` will abort with a
prompt demanding to select which account to use.  Bypass the prompt thus:

```
letsencrypt:
  hosts:
    example.org:
      account_number: 1
```
