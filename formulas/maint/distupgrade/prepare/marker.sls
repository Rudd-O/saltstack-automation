#!objects


if __salt__["file.file_exists"]("/.distupgrade"):
    curr = int(__salt__["file.read"]("/.distupgrade"))
else:
    curr = int(grains("osmajorrelease"))
next_ = curr + 1

File.managed(
    "Create distupgrade marker",
    name="/.distupgrade",
    contents=str(curr) + "\n" + str(next_),
)
