#!objects

from salt://lib/defs.sls import PillarConfigWithDefaults, ShowConfig


default_exclude_services = [
    "dbus.service",
    "systemd-logind.service",
    "xenstored.service",  # Breaks Xen.
    "xenconsoled.service",  # Breaks Xen consoles.
    "qubes-db-dom0.service",  # Breaks Qubes OS.
    "qubes-qrexec-policy-daemon.service",  # Boots off logged-in user in Qubes OS.
    "sddm.service",  # Logs out current session.
    "lightdm.service",  # Boots off logged-in user in Qubes OS.
    "kdm.service",  # Logs out current session.
    "qubes-qrexec-agent.service", # Logs out Salt itself.
    "qubes-gui-agent.service", # Logs out Salt itself.
    "auditd.service", # Can only be requested by dependency.
    "plymouth-start.service", # No need to restart.
    "^getty@",
    "^user@",
    ".+scope$",
]

default_exclude_paths = [
    "/run",
    "/home",
    "/tmp",
    "/memfd",
]

defaults = {
    "update": {
        "restart_exclude_paths": default_exclude_paths,
        "restart_exclude_services": default_exclude_services,
    },
    "distupgrade": {},
}

config = PillarConfigWithDefaults("maint", defaults, merge_lists=True)

ShowConfig(config)
