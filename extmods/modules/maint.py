import collections
import re
import subprocess

exclude_services = [
    "dbus.service",
    "auditd.service",
    "systemd-logind.service",
    "^getty@",
    "^user@",
    ".+scope$",
]

exclude_paths = [
    "/run",
    "/home",
    "/tmp",
]


def get_services_that_need_restart():
    needsrestart = ["needs-restart", "-b"]
    for p in exclude_paths:
        needsrestart.extend(["-i", p])
    svcs = [
        s
        for s in subprocess.check_output(
            needsrestart, universal_newlines=True
        ).splitlines()
        if s
    ]
    restartable = [s for s in svcs if not re.match("|".join(exclude_services), s)]
    nonrestartable = [s for s in svcs if re.match("|".join(exclude_services), s)]
    return {
        "restartable": restartable,
        "nonrestartable": nonrestartable,
    }


def is_service_failed(svc):
    p = subprocess.run(
        ["systemctl", "--system", "is-failed", svc],
        universal_newlines=True,
        capture_output=True,
    )
    return "failed" in p.stdout or "failed" in p.stderr


def restart_services(test=False):
    res = {
        "restarted": [],
        "failed": collections.OrderedDict(),
    }
    svcs = get_services_that_need_restart()
    for svc in svcs["restartable"]:
        restart = ([] if not test else ["echo"]) + [
            "systemctl",
            "--system",
            "restart",
            svc,
        ]
        p = subprocess.run(restart, universal_newlines=True, capture_output=True)
        if p.returncode == 0:
            res["restarted"].append(svc)
        else:
            res["failed"][svc] = p.stderr
    for svc in svcs["restartable"]:
        if svc not in res["failed"]:
            if is_service_failed(svc):
                res["failed"][svc] = "Service is failed."
    res["nonrestartable"] = svcs["nonrestartable"]
    return res


def get_kernel_reboot_required():
    latest_kernel = subprocess.check_output(
        "ls -1 /boot/vmlinuz-*.`arch` --sort=time | head -1 | sed -s 's|/boot/vmlinuz-||'",
        shell=True,
        universal_newlines=True,
    ).strip()
    current_kernel = subprocess.check_output(
        "uname -r",
        shell=True,
        universal_newlines=True,
    ).strip()
    if latest_kernel != current_kernel:
        return f"System runs kernel {current_kernel} and needs to reboot to upgrade to kernel {latest_kernel}"
    return ""
