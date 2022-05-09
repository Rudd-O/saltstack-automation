# MTA formula

This formula sets up a Postfix mail transfer agent on the targeted host,
with:

* greylisting (on by default)
* Sender-Permitted-From (on by default, but no rejection of email sent by
  servers which fail SPF checks — only headers are attached to incoming mail)
* DKIM (on by default, but no rejection of improperly-signed e-mail —
  only headers are attached to incoming mail)

You can adjust all these services using pillar settings (detailed below).
That said, the settings to make SPF and DKIM *reject* mail don't seem to
work correctly.

## Let's encrypt support

This formula will by default also rely on the
[letsencrypt formula](../../letsencrypt) to set up a certificate for the
*MX hostname* of the server.  If the MTA you are setting up will be receiving
email for domain X.YZ, you must also:

1. set up the respective A and MX records for this machine, and wait
   until they are propagated:
   * an MX host record in domain X.YZ to point to this machine's hostname
   * an A record for the hostname to point to this machine's IP address
2. add the respective pillar for the MX host record in the `letsencrypt`
   pillar (refer to the documentation for the letsencrypt formula)

You can opt out of this by supplying your own `tls_key/cert_file` pillars
as explained below.

## Pillar documentation

All pillar values here must be nested under the `email:mta` top level variable.
Values are optional unless no default is stated.

### `hostname`

The host name that the mail server will use and identify as.

Defaults to the system's host name of the machine.

This should match the MX record pointing to this machine, ideally.
The letsencrypt pillar to generate a certificate for this machine should match
this, and the formula will abort if it isn't there.

### `domain`

The default domain name that the mail server will serve.

Defaults to host name of the machine minus the initial component before
the first dot.

Your server can receive mail for more than one `domain` — see the setting
`destination_domains`.

### `origin`

Specifies the domain that locally-posted mail appears to come from (for
e-mails *originated on* this server, rather than the the envelope `From:`
part of e-mails sent *through* it).

Defaults to the `hostname` parameter.

If this machine will handle mail for a whole domain, you may want to set
it to the value of the domain instead.

### `destination_domains`

Specifies which domains the server will accept mail for.
Mail sent to the MTA machine for domains not listed here will be rejected.

The default value is generated based on the recipients and forwardings lists.
Each domain used in one of the addresses or alias sources will be listed here.

### `mynetworks`

List of IP networks (x.y.z.w/n) the server will accept mail from, without
any authentication.  Clients connecting with valid SMTP authentication can
send mail from IP address.  Be careful what you set this to — you may
end up with an open relay, spamming the entire world.

Defaults to `["127.0.0.1/8", "[::1]/128"]` (local loopback addresses).

### `message_size_limit`, `mailbox_size_limit`

Sets maximum size in bytes of received / transmitted messages, and mailbox,
respectively.

The defaults for max message size is 50 MB and for mailbox is 10 GB. 

### `recipient_delimiter`

Defaults to `.+`.

String of characters, any of which is accepted as delimiter for account names.

Id est, if your account name is `homer`, and someone mails `homer+abc@yourdomain`
or `homer.cdf@yourdomain`, both mails would be accepted to the account `homer`
under the default value of `recipient_delimiters`.

### `tls_key_file`, `tls_cert_file`

Sets paths to the TLS certificate files for the server, if you are using your
own custom SSL certificates for the MX hostname of the machine, rather than rely
on the built-in letsencrypt support.  This automatically disables letsencrypt
use.

### `greylisting`

Defaults to on.

When enabled, incoming mail goes through greylisting.  This reduces spam.

### `dkim:MinimumKeyBits`

Defaults to 2048.

Sets the minimum bits (powers of two integer) of acceptable keys and signatures.

### `dkim:keys`

Optional.

If unspecified, OpenDKIM will not sign outgoing mail.  If specified, OpenDKIM
will sign outgoing mail for the specified domains.

This must be a dictionary of the form:

```
email:
  mta:
    dkim:
      keys:
        mydomain.com: <DKIM private key string>
```

These keys will be used by OpenDKIM per-domain as the private key for
that domain, and DKIM signatures of outgoing mail will be enabled.

You should list a DKIM private key for each domain your server will send
outgoing mail as (in other words: generally all domains listed in your
`destination_domains` should have a DKIM private key). The corresponding
public key should be published in a DNS TXT record
`_default._domainkey.domain.com` for that domain.

To generate these keys, create a directory `test` and change into that
directory, then run command
`opendkim-genkey -s default --domain <domain name>` -- you will then find
file `default.txt` with the DNS TXT record to add to your domain name server,
and `default.private` will have the text you must add in the pillar shown
above.

### `dkim:On-*`

This is a collection of different DKIM conditional responses you can setup.

**These options do not appear to work as of the writing of this document.**
Nonetheless, the DKIM service will add a `dkim=<result>` header to each
received mail, which you can use to filter in your mail user agent, and will
be picked up by the spam filter as well.

By default (more or less) the DKIM service lets e-mail with invalid signatures
pass.  If you are not too afraid of losing e-mail improperly signed, you may
want to tweak `On_BadSignature` to `reject` those messages.  Before doing so,
it is recommended to look at the `journalctl` logs for messages coming from
`opendkim` to see what decisions it has made in the past.

Documentation for these parameters is available in the [man page for OpenDKIM
configuration](http://www.opendkim.org/opendkim.conf.5.html).  The key options
to tighten rejection of unsigned/invalidly-signed e-mail are:

* `On-BadSignature: reject`
* `On-SignatureError: reject`
* `On-NoSignature: reject`
* `On-KeyNotFound: reject`

### `spf:debugLevel`

Default `1`.  Note initial lowercase in name.

### `spf:TestOnly`

Default `0`.  Note initial uppercase in name.

You may want to set this to `1` initially, and watch your `journalctl` logs
for a while, before rejecting any e-mail contingent on SPF failures.

### `spf:HELO_reject`

Default `Fail`.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:HELO_pass_restriction`

Default empty.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:Mail_From_reject`

Default `Fail`.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:Mail_From_pass_restriction`

Default empty.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:Reject_Not_Pass_Domains`

Default empty.  Must be a list of strings, if specified.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:PermError_reject`

Default `False`.  Switch to true in order to reject mail with permanent SPF errors.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:TempError_Defer`

Default `False`.  Switch to true in order to belay mail with temporary SPF errors.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:skip_addresses`

Defaults to a list of local IP addresses with or without /n masks.  Must be a list if specified.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:Whitelist`

Defaults to a list of local IP addresses with or without /n masks to skip SPF checks for.  Must be a list if specified.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:HELO_Whitelist`

A list of domains to skip SPF checks for, during HELO/EHLO.  Empty by default.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:Domain_Whitelist`

A list of domains to skip SPF checks for.  Empty by default.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

### `spf:Domain_Whitelist_PTR`

A list of domains to skip SPF checks for, based on DNS PTR record match.  Empty by default.

See file [spf/policyd-spf.conf.j2] and documentation for python-policyd-spf for information.

