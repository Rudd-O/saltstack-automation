def devices_from_crypttab(file="/etc/crypttab"):
    """
    Return a dictionary of {
        device path => {
            keyfile: <path or None>.
            path: <path to device>,
        }
    }
    for each device specified in `file` (default /etc/crypttab).
    """
    text = __salt__["file.read"](file)
    lines = text.splitlines()
    devs = {}
    for line in lines:
        if not line.strip() or line.startswith("#"):
            continue
        try:
            dev = line.split()[1]
        except IndexError:
            continue

        if dev.startswith("UUID="):
            dev = "/dev/disk/by-uuid/" + dev[5:]
        else:
            dev = "/dev/" + dev

        try:
            keyfile = line.split()[2]
        except IndexError:
            keyfile = "none"
        devs[dev] = dict(path=dev, keyfile=None if keyfile in ("none", "-") else keyfile)
    return devs
