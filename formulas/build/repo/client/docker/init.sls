#!objects

import base64
import json

from salt://lib/qubes.sls import rw_only
from salt://lib/defs.sls import Perms
from salt://build/repo/config.sls import config


r = Test.nop('Docker repo deployed').requisite

if not rw_only() and "registry_url" in config.client.docker:
    context = config.client.docker
    slsp = sls.replace(".", "/")
    cfg = File.managed(
        '/etc/containers/registries.conf.d/dragonfear.conf',
        source=f'salt://{slsp}/registries.conf.j2',
        template='jinja',
        makedirs=True,
        context=context,
        **Perms.file,
    ).requisite
    upw = base64.b64encode(
        (
            "%s:%s" % (
                context.username,
                context.password,
            )
        ).encode("utf-8")
    ).decode("utf-8")
    auth = {
        "auths": {
            context.registry_url.split("//")[-1]: {
                "auth": upw
            }
        }
    }
    File.managed(
        '/root/.config/containers/auth.json',
        contents=json.dumps(auth),
        require=[cfg],
        makedirs=True,
        require_in=[r],
        **Perms.owner_file,
    )
