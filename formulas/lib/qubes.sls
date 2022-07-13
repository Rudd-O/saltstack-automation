#!pyobjects

from salt://lib/defs.sls import Perms

try:
    from shlex import quote
except ImportError:
    from pipes import quote


def dom0():
    return grains('qubes:vm_type') == "AdminVM"


def fully_persistent_or_physical():
    return grains('qubes:persistence') in ('full', '')


def fully_persistent():
    return grains('qubes:persistence') in ('full',)


def rw_only_or_physical():
    return grains('qubes:persistence') in ('rw-only', '')


def template():
    return grains('qubes:vm_type') == "TemplateVM"


def physical():
    return grains('qubes:persistence') in ('')


def updateable():
    return grains('qubes:updateable', False)


def rw_only():
    return grains('qubes:persistence') in ('rw-only',)


def Qubify(name, scope='system', qubes_service_name=None, require=None):
    if not require:
        require=[]
    if qubes_service_name is None:
        qubes_service_name = name
    nopname = "Qubified %s service %s" % (scope, qubes_service_name)
    if grains('qubes:persistence') in ('full',):
        # FIXME Service enabled must support user scope as well.
        with Service.enabled(name, require=require):
            File.directory(
                "/etc/systemd/%s/%s.service.d" % (scope, name),
                user="root",
                group="root",
                mode="0755"
            )
            File.managed(
                "/etc/systemd/%s/%s.service.d/qubes.conf" % (scope, name),
                contents="""[Unit]
ConditionPathExists=/var/run/qubes-service/%s
""" % qubes_service_name,
                user="root",
                group="root",
                mode="0644",
                require=File("/etc/systemd/%s/%s.service.d" % (scope, name))
            )
            Test.nop(nopname, require=[File("/etc/systemd/%s/%s.service.d/qubes.conf" % (scope, name))])
    else:
        Test.nop(nopname)
    return Test(nopname)


def RpcPolicy(name, contents):
    n = "/etc/qubes-rpc/policy/" + name
    return File.managed(
        n,
        contents=contents,
        user="root",
        group="qubes",
        **Perms.dir
    ).requisite


def BindDirs(name, directories, require=None):
    require = require or []
    if grains('qubes:persistence') in ('rw-only',):
        File.directory(
            '/rw/config/qubes-bind-dirs.d for %s' % name,
            name='/rw/config/qubes-bind-dirs.d',
            user='root', group='root', mode='0755'
        )
        lines = [
            "binds+=( %s )" % quote(f)
            for f in directories
        ]
        File.managed(
            '/rw/config/qubes-bind-dirs.d/%s.conf' % name,
            contents="\n".join(lines),
            mode='0644',
            user='root',
            group='root',
            require=File('/rw/config/qubes-bind-dirs.d for %s' % name),
        )
        File.directory(
            '/rw/bind-dirs for %s' % name,
            name='/rw/bind-dirs',
            user='root', group='root', mode='0755',
            require=File('/rw/config/qubes-bind-dirs.d/%s.conf' % name)
        )
        preamble = '''
            set -e ; changed=no
        '''
        prog_tpl = '''
        test -e /rw/bind-dirs{0} || {{
          echo We must bind-dir {0} >&2
          changed=yes
          mkdir -p $(dirname /rw/bind-dirs%s )
          test -e {0} || mkdir -p {0}
          mkdir -p /rw/bind-dirs/$(dirname {0})
          cp -a {0} /rw/bind-dirs{0}
        }}
        mountpoint {0} >&2 || {{
          echo We must mount-dir {0} >&2
          changed=yes
          mount --bind /rw/bind-dirs{0} {0}
        }}
        '''
        progs = [
            prog_tpl.format(quote(f))
            for f in directories
        ]
        footnote = '''
        if [ "$changed" == "yes" ] ; then
            echo
            echo changed=yes
        fi
        '''
        program = "\n".join([preamble, "\n".join(progs), footnote])
        Cmd.run(
            'adjust-bind-dirs for %s' % name,
            name=program,
            stateful=True,
            require=[File('/rw/bind-dirs for %s' % name)] + require,
        )
    else:
        Cmd.wait('adjust-bind-dirs for %s' % name,
                 name='echo Nothing needs to be done -- this machine does not use bind-dirs.',
                 require=require)
    return Cmd('adjust-bind-dirs for %s' % name)
