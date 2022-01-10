import os
import shlex
import subprocess


def systemd_reload(name, user):
    return list(__salt__["state.single"]("cmd.run", "su - %s -c 'systemctl --user daemon-reload'" % shlex.quote(user)).values())[0]

def running(name, user, enable=False):
    def runas(cmd, user, use_subprocess=False):
        cmd = " ".join(shlex.quote(c) for c in cmd)
        if not use_subprocess:
            return __salt__["cmd.run"]("su - %s -c %s" % (shlex.quote(user), shlex.quote(cmd)))
        with open(os.devnull) as devnull:
            return subprocess.run("su - %s -c %s" % (shlex.quote(user), shlex.quote(cmd)), shell=True, stdin=devnull, capture_output=True)

    enableret = dict(result=False, changes={}, name=name, comment="Fallthrough error 1")
    startret = dict(result=False, changes={}, name=name, comment="Fallthrough error 2")
    if enable:
        r = runas(['systemctl', '--user', 'is-enabled', '--', name], user)
        if r == "static":
            enableret['comment'] = "Unit %s cannot be enabled -- it is static." % name
        elif r == "disabled":
            if __opts__["test"]:
                enableret["comment"] = "Would have enabled unit %s." % name
                enableret["changes"]["enabled"] = name
                enableret["result"] = None
            else:
                r = runas(['systemctl', '--user', 'enable', '--', name], user, use_subprocess=True)
                if r.returncode == 0:
                    enableret["comment"] = "Enabled unit %s." % name
                    enableret["changes"]["enabled"] = name
                    enableret["result"] = True
                else:
                    enableret["comment"] = r.stderr.strip()
        else:
            enableret["result"] = True
            enableret["comment"] = ""
             
    else:
        enableret["result"] = True
        enableret["comment"] = ""

    r = runas(['systemctl', '--user', 'is-active', '--', name], user)
    if r != "active":
        if __opts__["test"]:
            startret["comment"] = "Would have started unit %s." % name
            startret["changes"]["running"] = name
            startret["result"] = None
        else:
            r = runas(['systemctl', '--user', 'start', '--', name], user, use_subprocess=True)
            if r.returncode == 0:
                startret["comment"] = "Started unit %s." % name
                startret["changes"]["running"] = name
                startret["result"] = True
            else:
                startret["comment"] = r.stderr.strip()
    else:
        startret["comment"] = "Unit %s is already running." % name
        startret["result"] = True

    ret = {
        "result": False if (
            startret["result"] is False or enableret["result"] is False
        ) else None if (
            startret["result"] is None or enableret["result"] is None
        ) else True,
        "comment": ((enableret["comment"] + "  ") if enableret["comment"] else "") + startret["comment"],
        "name": name,
        "changes": {**startret["changes"], **enableret["changes"]},
    }
    return ret
    
