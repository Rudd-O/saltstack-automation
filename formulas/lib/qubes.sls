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
    File.managed(
        n,
        contents=contents,
        user="root",
        group="qubes",
        **Perms.dir
    )
    return File(n)


def ShutoffVm(vm_name, require=None, onchanges=None, role=None):
    # FIXME follow the pattern of QubesService below,
    # no longer using Salt.function to make it stateful.
    require = require or []
    onchanges = onchanges or []
    dom0 = pillar('qubes:dom0s:%s' % vm_name)
    vm_name = vm_name.split(".")[0]
    assert dom0, (vm_name, dom0)
    fname = 'Shutoff ' + vm_name + ' in ' + dom0
    if role:
        fname = fname + " for role " + role
    Salt.function(
        fname,
        name='cmd.run',
        tgt=dom0,
        tgt_type='list',
        arg=['qvm-shutdown --force --wait ' + quote(vm_name)],
        ssh=True,
        parallel=True,
        require=require,
        onchanges=onchanges,
    )
    return Salt(fname)


def QubesService(vm_name, services, require=None, onchanges=None, require_in=None):
    if type(services) is not list and type(services) is not tuple:
        services = [services]
    # FIXME: make a roster.sls helper for qubes dom0s,
    # because this snippet is repeated in the codebase.
    dom0 = pillar('qubes:dom0s:%s' % vm_name)
    # FIXME: make the update roster program generate a table of vm_names instead
    # of hardcoding here a period.
    vm_name = vm_name.split(".")[0]
    require = require or []
    onchanges = onchanges or []
    require_in = require_in or []
    fname = 'Enable services ' + ", ".join(services) + ' on ' + vm_name + ' in ' + dom0

    if not pillar('skip_dom0s') and dom0:
        Salt.state(
            fname,
            tgt=dom0,
            tgt_type='list',
            sls='orch.lib.qubes.qvm-service',
            pillar={"services": services, "vm_name": vm_name},
            ssh=True,
            require=require,
            onchanges=onchanges,
            require_in=require_in,
        )
        return Salt(fname)
    else:
        Test.nop(fname)
        return Test(fname)


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
