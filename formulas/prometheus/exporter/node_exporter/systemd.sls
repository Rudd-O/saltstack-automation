#!objects

Cmd.wait(
    "Reload systemd for node exporter",
    name="systemctl --system daemon-reload",
)
