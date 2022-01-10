import os
import subprocess
import sys


def __virtual__():
    return "mypkg"


def installed(name):
    if os.access("/usr/bin/qubes-dom0-update", os.X_OK):
        try:
            subprocess.check_call(["rpm", "-q", "--", name], stdout=sys.stderr)
            return {
                'name': name,
                'changes': {},
                'result': True,
                'comment': "All packages are already installed.",
            }
        except subprocess.CalledProcessError:
            if __opts__['test']:
                return {
                    'name': name,
                    'changes': {},
                    'result': None,
                    'comment': "Package %s would be installed." % name,
                }
            p = subprocess.Popen(["qubes-dom0-update", "-y", name],
                                 stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE,
                                 universal_newlines=True)
            stdout, stderr = p.communicate()
            r = p.wait()
            if r != 0:
                return {
                    'name': name,
                    'changes': {},
                    'result': False,
                    'comment': (
                        "Command failed with status code %s." % r
                        + "\nStdout:\n %s" % stdout
                        + "\nStderr:\n %s" % stderr
                    ),
                }
            else:
                return {
                    'name': name,
                    'changes': {
                        'installed': {
                            name: True,
                        }
                    },
                    'result': True,
                    'comment': (
                        "Stdout:\n %s" % stdout + "\nStderr:\n %s" % stderr
                    ),
                }
    else:
        return __states__['pkg.installed'](name=name)
