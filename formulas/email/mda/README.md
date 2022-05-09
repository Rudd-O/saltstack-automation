# MDA formula

This formula sets up a local mail delivery agent, mail recipients, aliases
and catchall delivery of e-mail.

The local mail delivery agent is only configured when the formula has been
instructed to create mail recipients.  In this case, this formula requires
a properly-setup MTA formula to work (it assumes that said formula's
properly-configured Postfix will relay email to the local mail delivery agent).
If no local recipients have been registered, the mail delivery agent becomes
`/bin/true` and any incoming mail meant for local accounts is simply
blackholed as a result.

## Pillar documentation

All pillar values here must be nested under the `email:mda` top level variable.
Values are optional unless no default is stated.

### `catchall_username`

Sets the default user name or e-mail addresses that gets the mail sent to all
common aliases defined in `/etc/aliases`.  If not explicitly set to `null`,
this will default to the first user name in the recipients list.

By default this formula will not enable catchall.

### `recipients`

A list of final recipients for mail, to be created locally.  A non-empty list
causes the Postfix MTA to be configured for local mail delivery.

The form of each element of the list is as follows:

```
recipients:
- user: username      # user's login user name
  password: p@ssword  # user's initial access password
                      # won't change after creation unless
                      # enforce_password is also set in this recipient
  name: User Name     # User's desired full name
  aliases:            # A list of email addresses this account receives.
  - info@domain.com   # assumes this server also handles domain.com mail
  - sales@domain2.com
# ...
```

### `forwardings`

A list of forwardings of the form:

```
forwardings:
- name: <user@domain>  # forwarder
  addresses:
  - first@domain1    # recipients of the forwarder
  - second@domain2   # recipients of the forwarder
  - third            # this can also be a local mail account
# ...
```

### `mailbox_type`

Either `maildir` or `mbox`.

The default is `maildir` since it is more modern.

There is no automigration of mail if you switch this setting after you've
received mail.  You can migrate each username's mailboxes by hand from
`mbox` format to `maildir` format with
`dsync -u yourusername mirror mbox:~/mail` as each user account, after
stopping Postfix, reconfiguring to change to `maildir` and restarting
Dovecot with the `maildir` mailbox type, and then the mailboxes will
be migrated from `~/mail` mbox to maildir in `~/Maildir`.
