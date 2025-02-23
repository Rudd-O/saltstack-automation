#!objects


if (
    __salt__["file.file_exists"]("/etc/selinux/config")
    and __salt__["file.search"]("/etc/selinux/config", pattern="SELINUX=enforcing")
    and "true" in __salt__["cmd.run"]("selinuxenabled && echo true || echo false")
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
