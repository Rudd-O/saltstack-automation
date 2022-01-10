import os
import subprocess


def _fail(ret, comment):
    ret['result'] = False
    ret['comment'] = comment
    return ret


def _already(ret, comment):
    ret['result'] = True
    ret['comment'] = comment
    return ret


def _wouldchange(ret, comment):
    ret['result'] = None
    ret['comment'] = comment
    return ret


def _changed(ret, comment):
    ret['result'] = True
    ret['comment'] = comment
    return ret


def _run(cmd, comm):
    p = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
    )
    out, _ = p.communicate(comm)
    exitcode = p.wait()
    return out, exitcode


def principal_database(name, password):
    ret = {
        'name': name,
        'result': False,
        'changes': {},
        'comment': '',
    }

    if os.path.isfile(name):
        return _already(ret, "Kerberos database at %s already exists" % name)

    ret['changes']['new'] = [name]

    if __opts__['test']:
        return _wouldchange(ret, 'Kerberos database at %s would be created' % name)

    out, exitcode = _run(
        "/usr/sbin/kdb5_util create -s".split(),
        "%s\n%s\n" % (password, password),
    )
    if exitcode != 0:
        return _fail(ret, 'kdb5_util create failed with return code %s.\n%s' % (exitcode, out))

    return _changed(ret, 'Kerberos database at %s created.\n%s' % (name, out))


def principal(name, password='', admin_principal='', admin_password='', local=False):
    ret = {
        'name': name,
        'result': False,
        'changes': {},
        'comment': '',
    }

    if "\t" in name or " " in name or "\n" in name:
        return _fail(ret, "Carriage returns and spaces are not permitted in principals.")

    if "\n" in password or "\n" in admin_password:
        return _fail(ret, "Carriage returns are not permitted in passwords.")

    if local:
        if admin_principal or admin_password:
            return _fail(ret, "Execution of kadmin in local mode does not use an admin principal or an admin password.")
        cmd = ["kadmin.local", "-q", "get_principal %s" % name]
        comm = ""
    else:
        if not admin_principal or not admin_password:
            return _fail(ret, "Execution of kadmin in non-local mode requires an admin principal and an admin password.")
        cmd = ["kadmin", "-p", admin_principal, "-q", "get_principal %s" % name]
        comm = admin_password

    out, exitcode = _run(cmd, comm)
    if exitcode != 0:
        return _fail(ret, "%s failed with return code %s.\n%s" % (" ".join(cmd), exitcode, out))

    if "does not exist" not in out:
        return _already(ret, "Kerberos principal %s already exists.\n%s" % (name, out))

    ret['changes']['new'] = [name]

    if __opts__['test']:
        return _wouldchange(ret, 'Kerberos principal %s would be created.' % name)

    parm = "" if password else "-randkey"
    comm = ("%s\n%s\n" % (password, password)) if password else ""
    cmd = "addprinc %s %s" % (parm, name)
    if local:
        cmd = ["kadmin.local", "-q", cmd]
    else:
        comm = ("%s\n" % (admin_password,)) + comm
        cmd = ["kadmin", "-p", admin_principal, "-q", cmd]

    out, exitcode = _run(cmd, comm)
    if exitcode != 0:
        return _fail(ret, "%s failed with return code %s.\n%s" % (" ".join(cmd), exitcode, out))

    return _changed(ret, "Kerberos principal %s created.\n%s" % (name, out))


def keytab_entry(name, admin_principal='', admin_password='', keytab="/etc/krb5.keytab"):
    ret = {
        'name': name,
        'result': False,
        'changes': {},
        'comment': '',
    }

    if "\t" in name or " " in name or "\n" in name:
        return _fail(ret, "Carriage returns and spaces are not permitted in keytab entries.")

    if "\t" in keytab or " " in keytab or "\n" in keytab:
        return _fail(ret, "Carriage returns and spaces are not permitted in keytab paths.")

    if "\n" in admin_password:
        return _fail(ret, "Carriage returns are not permitted in passwords.")

    if not admin_principal or not admin_password:
        return _fail(ret, "Execution of kadmin in non-local mode requires an admin principal and an admin password.")

    cmd = ["ktutil"]
    comm = "read_kt %s\nlist\n" % keytab

    out, exitcode = _run(cmd, comm)
    if exitcode != 0:
        return _fail(ret, "%s failed with return code %s.\n%s" % (" ".join(cmd), exitcode, out))

    y= []
    for line in [
        x.lstrip().split()[2]
        for x in out.splitlines()
        if not x.startswith("ktutil:")
        and not x.startswith("--")
        and not x.startswith("slot:")
    ]:
        y.append(line)
        if ("@" in name and line == name) or (line.startswith(name + "@")):
            return _already(ret, "Kerberos principal %s already exists in %s.\n%s" % (line, keytab, out))
    assert 0, y

    ret['changes']['new'] = [name]

    if __opts__['test']:
        return _wouldchange(ret, 'Kerberos principal %s would be added to %s.\n%s' % (name, keytab, out))

    comm = "%s\n" % admin_password
    cmd = ["kadmin", "-p", admin_principal, "-q", "ktadd -t %s %s" % (keytab, name)]

    out, exitcode = _run(cmd, comm)
    if exitcode != 0:
        return _fail(ret, "%s failed with return code %s.\n%s" % (" ".join(cmd), exitcode, out))

    return _changed(ret, "Kerberos principal %s added to %s.\n%s" % (name, keytab, out))
