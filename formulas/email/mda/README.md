# MDA formula

This formula sets up a local mail delivery agent, mail recipients, forwardings,
and catchall delivery of e-mail on a per-domain basis.

The local mail delivery agent is only configured when the formula has been
instructed to create mail recipients.  In this case, this formula requires
a properly-setup MTA formula to work (it assumes that said formula's
properly-configured Postfix will relay email to the local mail delivery agent).
If no local recipients have been registered, or the `enable` setting is forced
to False, the mail delivery agent becomes `/bin/true` and any incoming mail
meant for local accounts is simply blackholed as a result.

Unless the MDA formula is disabled (see below), this provides mailbox services
via secure IMAP, as well as Sieve, to clients.

All settings are documented below under heading *Pillar documentation*.

## Operation

What follows is only true when the mail delivery agent is enabled (see
`enable` pillar knob below).  This is usually only true if there are
recipients configured (again, see below).

### Receiving mail: the pipeline

An e-mail received by your server, and meant to reach one of the accounts
you set up, traverses through this pipeline:

1. It is received by Postfix.
2. Postfix pushes it through the greylisting policy service.
   * If the policy service declines to receive it, then Postfix replies
     to the sender's server with the customary greylisting temporary failure.
2. Postfix then pushes it through the SPF verifier.
   * The SPF verifier only adds headers to the message.  It does not reject
     any e-mail at this stage.
3. Then Postfix pushes it through the DKIM signature verifier.
   * The DKIM verifier only adds headers to the message.  It does not reject
     any e-mail at this stage.
4. It is pushed through `/usr/libexec/dovecot/deliver`.
   * The program pipes the mail to the Dovecot LDA.
5. Dovecot LDA runs the e-mail the following Sieve scripts:
   * `/var/lib/sieve/before.d/*.sieve`, which includes the spam classifier
     ruleset that places spam into the *SPAM* folder.
   * Your own account's `~/.dovecot.sieve`, which contains the rules you
     have created using your own mail client.
   * `/var/lib/sieve/after.d/*.sieve`, which runs after your own Sieve rules.
6. Based on the decision taken by these scripts, Dovecot LDA delivers the
   e-mail to the right folder.  Should no decision be taken by these scripts,
   then the e-mail is delivered to the *INBOX* folder of your account.

### Spam handling

#### Automatic classification

Spam classification happens upon delivery, where Dovecot's deliver agent
automatically runs unclassified mail through the `spamclassifier` sieve
(stored at `/var/lib/sieve/before.d/spamclassifier.sieve`) which in turn
runs them through the `spamclassifier` filter (stored at
`/usr/local/libexec/sieve/spamclassifier`).  The filter runs `bogofilter`
with the appropriate options to detect the spamicity of the message.
Once the filter is done and has added the spamicity headers to the
incoming message, the `spamclassifier` sieve places the resulting
message in the appropriate SPAM box, or continues processing other sieve
scripts until the message ends in the appropriate mailbox (usually INBOX).

Because the rule that classifies mail as spam executes before your own Sieve
rules, all of your e-mail will go through the classifier.  This may mean that,
during the first few days, `bogofilter` will have to catch up with what *you*
understand as spam and not spam, and a few e-mails will be misclassified.
Worry not, as the process is very easy (see the next section) and `bogofilter`
learns very quickly what counts as spam and what doesn't.

**SPF and DKIM interaction with spam handling**: `bogofilter` takes into
account mail headers when deciding what is spam and what isn't, so the headers
added by the SPF and DKIM validators will inform `bogofilter` quite reliably as
to the legitimacy of the e-mail it's receiving for classification.

#### Reclassification and retraining

If the classifier has made a mistake, you can reclassify e-mails as ham or as
spam by simply using your mail client as follows:

Move them from the folder they are stored in, into the folder *SPAM*
(for e-mail that was wrongly classified as proper e-mail) or into any other
folder that isn't the *Trash* folder (for e-mail wrongly classified as spam).

When you move mails to *SPAM*, the server automatically runs them
through the `bogofilter` classifier again, telling the classifer to deem those
messages as spam.  Then, the server files the e-mail into the *SPAM* folder.

When you move mails out of *SPAM* the server automatically runs them
through the classifier, deeming them as ham (not spam); immediately after that,
the server saves the message in the destination folder.

You'll discover quite quickly that `bogofilter` learns really well what
qualifies as spam and what does not, according to your own criteria.  It's
almost magic.  After a few days, pretty much every e-mail will be correctly
classified, with a false positive and false negative rate of less than 0.1%.

**Technical note**: The reclassification is mediated by global `imapsieve`
filters (deployed to `/var/lib/sieve/imapsieve`) that intercept message
moves to and from the *SPAM* folder, and then pipe the contents of the moved
message to `learn-ham` or `learn-spam` (both programs deployed to
`/usr/local/libexec/sieve`).

All reclassification events are noted to the user's systemd journal, with tag
`bogofilter-reclassify`.  No personal information is sent to the
journal.  You can verify that classification is working properly by simply
running `journalctl -fa` as the user who classifies the email, or
as root.  The events will appear in real-time, and if there is any problem
with the reclassifier, an error will be logged.

By default, incoming mail will be classified as spam or ham, but their
contents will not be registered as either in the `bogofilter` database.
This prevents false positives and negatives.  If you wish to turn on
automatic registration of incoming mail's contents as SPAM or ham, the
role variable `spam.autoregister_incoming_mail` can be turned on (set to
True), and then incoming mail will automatically be recorded as spam or
ham based on the decisions that `bogofilter` makes at the time.  This can
speed up the training process, but it can also cause `bogofilter` to
incorrectly learn what is spam and what isn't.

## Pillar documentation

All pillar values here must be nested under the `email:mda` top level variable.
Values are optional unless no default is stated.

You can verify the configuration as it applies to your host with
`salt host state.sls email.config`.

### `enable`

Defaults to `None`, meaning the mail delivery agent (which provides mailbox services
will only be enabled if there are recipients registered.

Set to `True` to forcibly enable the MDA even without recipients registered,
or `False` to prevent enabling the MDA even with registered recipients.

### `hostname`

Defaults to whatever the MTA hostname is.  This will be used to generate the
certificates that Dovecot will present to clients, if mailbox services are enabled.

### `tls_key_file`, `tls_cert_file`

Sets paths to the TLS certificate files for the server, if you are using your
own custom SSL certificates for the mailbox services hostname of the machine,
rather than rely on the built-in letsencrypt support.  This automatically disables
letsencrypt use.

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
  addresses:          # A list of email addresses this account receives.
                      # If the list is empty, this account will not receive
                      # any e-mail (unless set as catchall).
  - info@domain.com
  - sales@domain2.com
  # The following is a domain catchall:
  # - @domain3.com
# ...

#### Catch-all address for a domain

In a recipient, you can list an e-mail address without a user name part
(the at sign, then the domain) and this will act as a catch-all for that
domain, sending the e-mail to that recipient's mail account.

By default this formula will not enable any catch-all.

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

### `spam:train_spam_filter_with_incoming_mail`

If true (not the default) the spam filter will first evaluate incoming mail,
then use the result of the evaluation to reinforce its neural network.
This can result in faster learning of what is spam / what isn't spam, but
it can also result in very fast reinforcement of false positives.

By default the spam filter is only trained by your classification actions
in your client (send mail to SPAM folder, or pull mail out from SPAM folder).

### `spam:file_spam_after_user_scripts`

If true (not the default) the spam filer will only file e-mail as spam after
all the user classifier sieve scripts have executed.

The default is to file e-mail as spam as soon as it is detected as spam,
skipping user sieve scripts.

### `stats`

A dictionary permitting the configuration of stats (disabled by default)
where the following values can be set:

* `enable`: if true, enables statistics collection and exporting in a
  way compatible with Prometheus.
* `port`: TCP port where the Prometheus service will serve metrics, at
  the `/metrics` endpoint.
* `metrics`: which metrics to export (minimal defaults if enabled); see
  https://doc.dovecot.org/2.3/configuration_manual/stats/openmetrics/ for
  more information.
