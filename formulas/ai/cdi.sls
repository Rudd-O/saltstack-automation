#!objects

nct = Pkg.installed("golang-github-nvidia-container-toolkit").requisite

cdi_path = File.directory("/etc/cdi", require=[nct]).requisite

cdi = Cmd.run(
    "NVIDIA CDI",
    name="nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml",
    creates="/etc/cdi/nvidia.yaml",
    require=[cdi_path],
).requisite

sebool = Selinux.boolean(
    "NVIDIA access in containers",
    name="container_use_devices",
    value=True,
    persist=True,
    require=[cdi],
).requisite

pd = Pkg.installed("nvidia-persistenced").requisite

pds = Service.running(
    "nvidia-persistenced",
    enable=True,
    require=[pd],
)