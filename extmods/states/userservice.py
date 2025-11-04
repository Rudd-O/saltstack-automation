import os
import shlex
import subprocess


def systemd_reload(name, user):
    return list(__salt__["state.single"]("cmd.run", "systemctl --machine=%s@.host --user daemon-reload" % (shlex.quote(user),)).values())[0]


def _runas(cmd, user, use_subprocess=False):
    cmd = " ".join(shlex.quote(c) for c in cmd)
    if not use_subprocess:
        if user is not None:
            return __salt__["cmd.run"]("su - %s -c %s" % (shlex.quote(user), shlex.quote(cmd)))
        else:
            return __salt__["cmd.run"](cmd)
    with open(os.devnull) as devnull:
        if user is not None:
            return subprocess.run("su - %s -c %s" % (shlex.quote(user), shlex.quote(cmd)), shell=True, stdin=devnull, capture_output=True, text=True)
        else:
            return subprocess.run(cmd, shell=True, stdin=devnull, capture_output=True, text=True)



def running(name, user, enable=False):
    enableret = dict(result=False, changes={}, name=name, comment="Fallthrough error 1")
    startret = dict(result=False, changes={}, name=name, comment="Fallthrough error 2")
    if enable:
        r = _runas(['systemctl', '--machine=%s@.host' % user, '--user', 'is-enabled', '--', name], None)
        if r == "static":
            enableret['comment'] = "Unit %s cannot be enabled -- it is static." % name
        elif r == "disabled":
            if __opts__["test"]:
                enableret["comment"] = "Would have enabled unit %s." % name
                enableret["changes"]["enabled"] = name
                enableret["result"] = None
            else:
                r = _runas(['systemctl', '--machine=%s@.host' % user, '--user', 'enable', '--', name], None, use_subprocess=True)
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

    r = _runas(['systemctl', '--machine=%s@.host' % user, '--user', 'is-active', '--', name], None)
    if r != "active":
        if __opts__["test"]:
            startret["comment"] = "Would have started unit %s." % name
            startret["changes"]["running"] = name
            startret["result"] = None
        else:
            r = _runas(['systemctl', '--machine=%s@.host' % user, '--user', 'start', '--', name], None, use_subprocess=True)
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
    

def dead(name, user):
    startret = dict(result=False, changes={}, name=name, comment="Fallthrough error 2")
    r = _runas(['systemctl', '--machine=%s@.host' % user, '--user', 'is-active', '--', name], None)
    if r == "active":
        if __opts__["test"]:
            startret["comment"] = "Would have stopped unit %s." % name
            startret["changes"]["dead"] = name
            startret["result"] = None
        else:
            r = _runas(['systemctl', '--machine=%s@.host' % user, '--user', 'stop', '--', name], None, use_subprocess=True)
            if r.returncode == 0:
                startret["comment"] = "Stopped unit %s." % name
                startret["changes"]["dead"] = name
                startret["result"] = True
            else:
                startret["comment"] = r.stderr.strip()
    else:
        startret["comment"] = "Unit %s is already stopped." % name
        startret["result"] = True

    ret = {
        "result": False if (
            startret["result"] is False
        ) else None if (
            startret["result"] is None
        ) else True,
        "comment": startret["comment"],
        "name": name,
        "changes": {**startret["changes"]},
    }
    return ret

def linger(name, user):
    ret = list(__salt__["state.single"]("file.managed", f"/var/lib/systemd/linger/{user}", contents="").values())[0]
    ret["name"] = name
    return ret
