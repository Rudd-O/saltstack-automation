#!objects


parent = "/".join(sls.split(".")[:-1])

Cmd.script(
    "Snapshot root dataset",
    name="salt://" + parent + "/snapshot-root-dataset.sh",
    stateful=True,
)
