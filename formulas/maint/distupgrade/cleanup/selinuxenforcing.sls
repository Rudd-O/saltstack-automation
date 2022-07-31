#!objects


if (
    __salt__["file.file_exists"]("/etc/selinux/config")
    and not __salt__["file.contains"]("/etc/selinux/config", "SELINUX=disabled")
):
    Cmd.run(
        "setenforce 1",
        require_in=[File("Set SELinux to enforcing")],
    )
    File.replace(
        "Set SELinux to enforcing",
        name="/etc/selinux/config",
        pattern="^SELINUX=.*",
        repl='SELINUX=enforcing',
        append_if_not_found=True,
    )
else:
    Cmd.wait(
        "setenforce 1",
        require_in=[File("Set SELinux to enforcing")],
    )
    File.absent(
        "Set SELinux to enforcing",
        name="/.arnsoeitlaoirestnhywq4klv598arjdh97hqvghq89yhkr-syvh9wq7pht8yabsr",
    )
