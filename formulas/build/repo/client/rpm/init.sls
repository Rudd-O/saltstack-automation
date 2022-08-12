#!objects

import base64
import json
import shlex

from salt://lib/qubes.sls import rw_only
from salt://lib/defs.sls import Perms
from salt://build/repo/config.sls import config


r = Test.nop('RPM repo deployed').requisite

if not rw_only() and config.client.rpm.get("base_url"):
    context = config.client.rpm
    slsp = sls.replace(".", "/")
    k = File.managed(
        f'/etc/pki/rpm-gpg/RPM-GPG-KEY-{context.repo_name}',
        contents=context.gpg_key,
        **Perms.file,
    ).requisite
    File.managed(
        f'/etc/yum.repos.d/{context.repo_name}.repo',
        source=f'salt://{slsp}/dnf-updates.repo.j2',
        template='jinja',
        context=context,
        require_in=[r],
        **Perms.file,
    )
    qrn = shlex.quote(context.repo_name)
    Cmd.run(
        f'rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-{qrn}',
        onchanges=[k],
        require_in=[r],
    )
