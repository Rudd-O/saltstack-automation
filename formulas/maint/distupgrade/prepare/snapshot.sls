#!objects


curr = int(grains("osmajorrelease"))
next_ = curr + 1


parent = "/".join(sls.split(".")[:-1])

Cmd.script(
    "Snapshot root dataset",
    name="salt://" + parent + "/snapshot-root-dataset.sh",
    args="%s %s" % (curr, next_),
    stateful=True,
)
