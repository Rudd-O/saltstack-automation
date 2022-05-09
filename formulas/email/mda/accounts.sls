#!objects

from salt://email/config.sls import config


context = config["mda"].get("recipients")

if context:
    for u in context:
        optionals = {}
        if "password" in u:
            optionals["password"] = u["password"]
            optionals["hash_password"] = True
            optionals["enforce_password"] = u.get("enforce_password", False)
        optionals["shell"] = u.get("shell", "/sbin/nologin")
        if "name" in u:
            optionals["fullname"] = u["name"]
            
        User.present(
            f"Mail recipient {u['user']}",
            name=u["user"],
            system=False,
            **optionals,
        )

        File.managed(
            f"/var/mail/{u['user']}",
            require=[User(f"Mail recipient {u['user']}")],
            mode="0660",
            user=u['user'],
            group="mail",
            require_in=[Test("All local recipients created")],
        )

        if config["mda"]["mailbox_type"] == "mbox":
    
            File.directory(
                f"~{u['user']}/mail",
                require=[User(f"Mail recipient {u['user']}")],
                mode="0700",
                user=u['user'],
            )

            for f in "inbox SPAM":
                File.managed(
                    f"~{u['user']}/mail/{f}",
                    require=[File(f"~{u['user']}")],
                    mode="0600",
                    user=u['user'],
                    require_in=[Test("All local recipients created")],
                )

        else:

            File.directory(
                f"~{u['user']}/Maildir",
                require=[User(f"Mail recipient {u['user']}")],
                mode="0700",
                user=u['user'],
            )

            for f in "cur new tmp .SPAM".split():
                File.directory(
                    f"~{u['user']}/Maildir/{f}",
                    require=[File(f"~{u['user']}/Maildir")],
                    mode="0700",
                    user=u['user'],
                    require_in=[Test("All local recipients created")],
                )
                
            for f in "cur new tmp".split():
                File.directory(
                    f"~{u['user']}/Maildir/.SPAM/{f}",
                    require=[File(f"~{u['user']}/Maildir/.SPAM")],
                    mode="0700",
                    user=u['user'],
                    require_in=[Test("All local recipients created")],
                )

Test.nop(
    "All local recipients created",
)
