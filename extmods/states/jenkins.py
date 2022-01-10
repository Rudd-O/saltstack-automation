import logging
import time


log = logging.getLogger(__name__)

def plugins_installed(name, plugins, jenkins_url, username, password):
    ret = dict(name=name, result=False, changes={}, comment="")
    e = lambda: __salt__['jenkins.existing_plugins_and_versions'](jenkins_url, username, password)
    existing = set(e())
    log.info("Existing plugins and versions: %s", existing)
    to_install = set(plugins) - existing
    if not to_install:
        ret["result"] = True
        return ret
    if __opts__["test"]:
        ret["result"] = None
        ret["changes"] = {"installed": list(to_install)}
        ret["comment"] = "Some plugins would be installed: %s" % ", ".join(to_install)
        return ret
    log.info("Requesting install of plugins: %s", to_install)
    if to_install:
        __salt__['jenkins.install_plugins'](to_install, jenkins_url, username, password)
    remaining_to_install = to_install
    for _ in range(120):
        remaining_to_install = set(plugins) - set(e())
        log.info("Still remaining to install: %s", remaining_to_install)
        if not remaining_to_install:
            ret["result"] = True
            ret["changes"] = {"installed": list(to_install)}
            return ret
        time.sleep(1)
    ret["changes"] = {"not installed": list(remaining_to_install), "installed": list(to_install - remaining_to_install)}
    ret["comment"] = "Some plugins were never installed: %s" % ", ".join(remaining_to_install)
    return ret
