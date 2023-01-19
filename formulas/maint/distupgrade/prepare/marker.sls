#!objects


if __salt__["file.file_exists"]("/.distupgrade"):
    data = __salt__["file.read"]("/.distupgrade").splitlines()
    curr = int(data[0])
    next_ = int(data[-1])
else:
    curr = int(grains("osmajorrelease"))
    next_ = curr + 1

File.managed(
    "Create distupgrade marker",
    name="/.distupgrade",
    contents=str(curr) + "\n" + str(next_),
)
