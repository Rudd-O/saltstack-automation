#!objects


if __salt__["file.file_exists"]("/etc/cdi/nvidia.yaml"):
    cdi = Cmd.run(
        "NVIDIA CDI",
        name="nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml",
    ).requisite
else:
    cdi = None

b = Test.nop("Before NVIDIA CDI", require_in=[cdi] if cdi else []).requisite

Test.nop("After NVIDIA CDI", require=[cdi] if cdi else [b])