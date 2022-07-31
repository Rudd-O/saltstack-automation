#!objects


if (
    __salt__["file.file_exists"]("/etc/selinux/config")
    and not __salt__["file.contains"]("/etc/selinux/config", "SELINUX=disabled")
):
    File.replace(
        "Set SELinux to permissive",
        name="/etc/selinux/config",
        pattern="^SELINUX=.*",
        repl='SELINUX=permissive',
        append_if_not_found=True,
    )
    Cmd.wait(
        "setenforce 0",
        watch=[File("Set SELinux to permissive")],
    )
else:
    File.absent(
        "Set SELinux to permissive",
        name="/.arnsoeitlaoirestnhywq4klv598arjdh97hqvghq89yhkr-syvh9wq7pht8yabsr",
    )
    Cmd.wait(
        "setenforce 0",
        name="echo setenforce 0",
        watch=[File("Set SELinux to permissive")],
    )
