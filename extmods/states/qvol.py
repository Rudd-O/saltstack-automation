import subprocess


def size_to_bytes(size):
    size = str(size)
    if size.endswith("G"):
        size = str(int(size[:-1]) * 1024 * 1024 * 1024)
    elif size.endswith("M"):
        size = str(int(size[:-1]) * 1024 * 1024)
    elif size.endswith("K"):
        size = str(int(size[:-1]) * 1024)
    return size


def set_size(name, volume, size):
    size = size_to_bytes(size)
    ret = {
        "name": name,
        "comment": "",
        "changes": {},
        "result": False,
    }
    try:
        current = subprocess.check_output(
            ["qvm-volume", "info", "{name}:{volume}".format(**locals()), "size"],
            universal_newlines=True,
        ).rstrip()
    except (subprocess.CalledProcessError, OSError) as e:
        ret["comment"] = str(e)
        return ret

    if size == current:
        ret['result'] = True
        return ret
    
    if __opts__['test']:
        ret['comment'] = "Volume %s of VM %s would be resized from %s to %s" % (name, volume, current, size)
        ret['changes'] = {volume: size}
        ret['result'] = None
        return ret

    p = subprocess.Popen(
        ["qvm-volume", "resize", "{name}:{volume}".format(**locals()), size],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
    )
    output, _ = p.communicate()
    output = output.rstrip()
    returncode = p.wait()
    if returncode == 0:
        ret['comment'] = "Volume %s of VM %s resized from %s to %s" % (name, volume, current, size) + "\n" + output
        ret['changes'] = {volume: size}
        ret['result'] = True
    else:
        ret["comment"] = "Failed executing qvm-volume resize\n" + str(output)
    return ret
