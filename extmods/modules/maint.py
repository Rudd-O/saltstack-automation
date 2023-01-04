import collections
import os
import re
import subprocess


def get_services_that_need_restart(exclude_services_globs=None, exclude_paths=None):
    exclude_services_globs = exclude_services_globs or []
    exclude_paths = exclude_paths or []
    needsrestart = ["needs-restart", "-b", "-u"]
    for p in exclude_paths:
        needsrestart.extend(["-i", p])
    try:
        needsrestartoutput = subprocess.run(
            needsrestart,
            text=True,
            capture_output=True,
            check=True,
        )
        needsrestartreport = subprocess.run(
            ["needs-restart"],
            text=True,
            capture_output=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        return {
            "command": exc.cmd,
            "error": exc.stderr,
        }
    except FileNotFoundError:
        return {
            "command": "no command",
            "error": "needs-restart not found"
        }
    svcs = [s for s in needsrestartoutput.stdout.splitlines() if s]
    restartable = [s for s in svcs if not exclude_services_globs or not re.match("|".join(exclude_services_globs), s)]
    nonrestartable = [s for s in svcs if exclude_services_globs and re.match("|".join(exclude_services_globs), s)]
    return {
        "restartable": restartable,
        "nonrestartable": nonrestartable,
        "report": needsrestartreport.stdout.rstrip(),
    }


def is_service_failed(svc):
    p = subprocess.run(
        ["systemctl", "--system", "is-failed", svc],
        universal_newlines=True,
        capture_output=True,
    )
    return "failed" in p.stdout or "failed" in p.stderr


def restart_services(test=False, exclude_services_globs=None, exclude_paths=None):
    exclude_services_globs = exclude_services_globs or []
    exclude_paths = exclude_paths or []
    svcs = get_services_that_need_restart(exclude_services_globs, exclude_paths)
    if "error" in svcs:
        return {
            "restarted": [],
            "failed": {"needs-restart": svcs["command"]},
            "report": svcs["error"],
        }
    res = {
        "restarted": [],
        "failed": collections.OrderedDict(),
        "report": svcs["report"],
    }
    for svc in svcs["restartable"]:
        # Log which services will be restarted.
        dofake = "fake " if test else ""
        subprocess.run(
            ["logger", "-t", "needs-restart", f"Will now {dofake}restart service {svc}"]
        )
        restart = ([] if not test else ["echo"]) + (
            ["systemctl", "--system", "restart", svc]
        )
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
    with open(os.devnull, "a") as f:
        # Optimistically run the unit state collector, ignoring errors.
        subprocess.call(
            "systemctl --system start --no-block systemd-unit-state-collector".split(),
            stdin=None,
            stdout=f,
            stderr=f,
        )
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


def get_xen_reboot_required():
    try:
        latest_xen = subprocess.check_output(
            "set -o pipefail ; rpm -q --queryformat=%{version} xen-hypervisor | sort -gr",
            shell=True,
            universal_newlines=True,
        ).strip()
    except subprocess.CalledProcessError:
        # No RPM.
        return ""
    try:
        current_xen = subprocess.check_output(
            "set -o pipefail ; xl info | grep ^xen_version | cut -d : -f 2",
            shell=True,
            universal_newlines=True,
        ).strip()
    except subprocess.CalledProcessError:
        # No Xen.
        return ""
    if latest_xen != current_xen:
        return f"System runs Xen {current_xen} and needs to reboot to upgrade to kernel {latest_xen}"
    return ""
