# To-do items.

Activate the following (from the release notes of Postfix 3.6.0).

Fine-grained control over the envelope sender address for submission with the Postfix sendmail (or postdrop) commands.

Example:

/etc/postfix/main.cf:
    # Allow root and postfix full control, anyone else can only
    # send mail as themselves. Use "uid:" followed by the numerical
    # UID when the UID has no entry in the UNIX password file.
    local_login_sender_maps =
        inline:{ { root = *}, { postfix = * } },
        pcre:/etc/postfix/login_senders

/etc/postfix/login_senders:
   # Allow both the bare username and the user@domain forms.
    /(.+)/ $1 $1@example.com

